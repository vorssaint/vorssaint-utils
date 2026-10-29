// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Copy for the option that keeps email links from opening Mail.
struct MailBlockStrings {
    let hubTitle: String
    let hubDescription: String
    let section: String
    let title: String
    let caption: String
    let actionLabel: String
    let actionIgnore: String
    let actionOpenApp: String
    let actionCopy: String
    let appLabel: String
    let appNone: String
    let chooseApp: String
    let appRejected: String
    let unavailable: String
    let copied: String
}

extension FeatureStrings {
    static func mailBlock(_ language: AppLanguage) -> MailBlockStrings {
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

extension MailBlockStrings {
    static let enUS = MailBlockStrings(
        hubTitle: "Mail link blocker",
        hubDescription: "Keep email links from opening Mail",
        section: "Email links",
        title: "Stop email links from opening Mail",
        caption: "Vorssaint takes email links in place of Mail and does what you choose below. Turning this off gives them back to the app that had them.",
        actionLabel: "When a link is clicked",
        actionIgnore: "Do nothing",
        actionOpenApp: "Open in another app",
        actionCopy: "Copy the address",
        appLabel: "App",
        appNone: "None",
        chooseApp: "Choose app…",
        appRejected: "Mail is the app being blocked, so it can’t open these links. Choose another app.",
        unavailable: "Email links couldn’t be taken over right now. Turn this off and on to try again.",
        copied: "Email address copied"
    )

    static let ptBR = MailBlockStrings(
        hubTitle: "Bloqueio de links do Mail",
        hubDescription: "Impede que links de e-mail abram o Mail",
        section: "Links de e-mail",
        title: "Impedir que links de e-mail abram o Mail",
        caption: "O Vorssaint recebe os links de e-mail no lugar do Mail e faz o que você escolher abaixo. Ao desligar, eles voltam para o app que os abria antes.",
        actionLabel: "Ao clicar em um link",
        actionIgnore: "Não fazer nada",
        actionOpenApp: "Abrir em outro app",
        actionCopy: "Copiar o endereço",
        appLabel: "App",
        appNone: "Nenhum",
        chooseApp: "Escolher app…",
        appRejected: "O Mail é o app bloqueado, então não pode abrir esses links. Escolha outro app.",
        unavailable: "Não foi possível assumir os links de e-mail agora. Desligue e ligue a opção para tentar novamente.",
        copied: "Endereço de e-mail copiado"
    )

    static let tr = MailBlockStrings(
        hubTitle: "Mail bağlantı engelleyici",
        hubDescription: "E-posta bağlantılarının Mail’i açmasını önler",
        section: "E-posta bağlantıları",
        title: "E-posta bağlantılarının Mail’i açmasını engelle",
        caption: "Vorssaint e-posta bağlantılarını Mail yerine alır ve aşağıda seçtiğinizi yapar. Kapatıldığında bağlantılar önceki uygulamaya geri verilir.",
        actionLabel: "Bir bağlantıya tıklandığında",
        actionIgnore: "Hiçbir şey yapma",
        actionOpenApp: "Başka bir uygulamada aç",
        actionCopy: "Adresi kopyala",
        appLabel: "Uygulama",
        appNone: "Yok",
        chooseApp: "Uygulama seç…",
        appRejected: "Engellenen uygulama Mail olduğu için bu bağlantıları açamaz. Başka bir uygulama seçin.",
        unavailable: "E-posta bağlantıları şu anda devralınamadı. Yeniden denemek için kapatıp açın.",
        copied: "E-posta adresi kopyalandı"
    )

    static let ru = MailBlockStrings(
        hubTitle: "Блокировка ссылок Почты",
        hubDescription: "Не даёт ссылкам на e-mail открывать Почту",
        section: "Ссылки на e-mail",
        title: "Не открывать Почту по ссылкам на e-mail",
        caption: "Vorssaint принимает ссылки на e-mail вместо Почты и делает то, что выбрано ниже. После выключения ссылки возвращаются приложению, которое открывало их раньше.",
        actionLabel: "При нажатии на ссылку",
        actionIgnore: "Ничего не делать",
        actionOpenApp: "Открыть в другом приложении",
        actionCopy: "Скопировать адрес",
        appLabel: "Приложение",
        appNone: "Нет",
        chooseApp: "Выбрать приложение…",
        appRejected: "Почта как раз блокируется, поэтому не может открывать эти ссылки. Выберите другое приложение.",
        unavailable: "Сейчас не удалось перехватить ссылки на e-mail. Выключите и снова включите опцию, чтобы повторить попытку.",
        copied: "Адрес e-mail скопирован"
    )

    static let es = MailBlockStrings(
        hubTitle: "Bloqueo de enlaces de Mail",
        hubDescription: "Evita que los enlaces de correo abran Mail",
        section: "Enlaces de correo",
        title: "Evitar que los enlaces de correo abran Mail",
        caption: "Vorssaint recibe los enlaces de correo en lugar de Mail y hace lo que elijas abajo. Al desactivarlo, vuelven a la app que los abría antes.",
        actionLabel: "Al hacer clic en un enlace",
        actionIgnore: "No hacer nada",
        actionOpenApp: "Abrir en otra app",
        actionCopy: "Copiar la dirección",
        appLabel: "App",
        appNone: "Ninguna",
        chooseApp: "Elegir app…",
        appRejected: "Mail es la app bloqueada, así que no puede abrir estos enlaces. Elige otra app.",
        unavailable: "No se pudieron tomar los enlaces de correo ahora. Desactiva y activa la opción para volver a intentarlo.",
        copied: "Dirección de correo copiada"
    )

    static let sk = MailBlockStrings(
        hubTitle: "Blokovanie odkazov Mailu",
        hubDescription: "Zabráni, aby e-mailové odkazy otvárali Mail",
        section: "E-mailové odkazy",
        title: "Nedovoliť e-mailovým odkazom otvárať Mail",
        caption: "Vorssaint preberá e-mailové odkazy namiesto Mailu a urobí to, čo vyberiete nižšie. Po vypnutí sa odkazy vrátia apke, ktorá ich otvárala predtým.",
        actionLabel: "Po kliknutí na odkaz",
        actionIgnore: "Nerobiť nič",
        actionOpenApp: "Otvoriť v inej apke",
        actionCopy: "Skopírovať adresu",
        appLabel: "Apka",
        appNone: "Žiadna",
        chooseApp: "Vybrať apku…",
        appRejected: "Mail je blokovaná apka, preto tieto odkazy nemôže otvárať. Vyberte inú apku.",
        unavailable: "E-mailové odkazy sa teraz nepodarilo prevziať. Vypnite a znova zapnite túto možnosť.",
        copied: "E-mailová adresa skopírovaná"
    )

    static let de = MailBlockStrings(
        hubTitle: "Mail-Link-Blocker",
        hubDescription: "Verhindert, dass E-Mail-Links Mail öffnen",
        section: "E-Mail-Links",
        title: "E-Mail-Links öffnen Mail nicht mehr",
        caption: "Vorssaint übernimmt E-Mail-Links statt Mail und tut, was du unten wählst. Beim Ausschalten gehen sie an die App zurück, die sie vorher geöffnet hat.",
        actionLabel: "Beim Klick auf einen Link",
        actionIgnore: "Nichts tun",
        actionOpenApp: "In anderer App öffnen",
        actionCopy: "Adresse kopieren",
        appLabel: "App",
        appNone: "Keine",
        chooseApp: "App wählen …",
        appRejected: "Mail ist die blockierte App und kann diese Links daher nicht öffnen. Wähle eine andere App.",
        unavailable: "E-Mail-Links konnten gerade nicht übernommen werden. Schalte die Option aus und wieder ein, um es erneut zu versuchen.",
        copied: "E-Mail-Adresse kopiert"
    )

    static let fr = MailBlockStrings(
        hubTitle: "Blocage des liens Mail",
        hubDescription: "Empêche les liens e-mail d’ouvrir Mail",
        section: "Liens e-mail",
        title: "Empêcher les liens e-mail d’ouvrir Mail",
        caption: "Vorssaint reçoit les liens e-mail à la place de Mail et fait ce que vous choisissez ci-dessous. Une fois désactivé, ils reviennent à l’app qui les ouvrait avant.",
        actionLabel: "Au clic sur un lien",
        actionIgnore: "Ne rien faire",
        actionOpenApp: "Ouvrir dans une autre app",
        actionCopy: "Copier l’adresse",
        appLabel: "App",
        appNone: "Aucune",
        chooseApp: "Choisir une app…",
        appRejected: "Mail est l’app bloquée, elle ne peut donc pas ouvrir ces liens. Choisissez une autre app.",
        unavailable: "Impossible de prendre en charge les liens e-mail pour le moment. Désactivez puis réactivez l’option pour réessayer.",
        copied: "Adresse e-mail copiée"
    )

    static let it = MailBlockStrings(
        hubTitle: "Blocco dei link di Mail",
        hubDescription: "Impedisce ai link email di aprire Mail",
        section: "Link email",
        title: "Impedisci ai link email di aprire Mail",
        caption: "Vorssaint riceve i link email al posto di Mail e fa ciò che scegli qui sotto. Disattivandolo, tornano all’app che li apriva prima.",
        actionLabel: "Quando fai clic su un link",
        actionIgnore: "Non fare nulla",
        actionOpenApp: "Apri in un’altra app",
        actionCopy: "Copia l’indirizzo",
        appLabel: "App",
        appNone: "Nessuna",
        chooseApp: "Scegli app…",
        appRejected: "Mail è l’app bloccata, quindi non può aprire questi link. Scegli un’altra app.",
        unavailable: "Impossibile gestire i link email in questo momento. Disattiva e riattiva l’opzione per riprovare.",
        copied: "Indirizzo email copiato"
    )

    static let ja = MailBlockStrings(
        hubTitle: "メールリンクブロック",
        hubDescription: "メールのリンクで“メール”が開かないようにする",
        section: "メールのリンク",
        title: "メールのリンクで“メール”を開かない",
        caption: "Vorssaintが“メール”の代わりにメールのリンクを受け取り、下で選んだ動作をします。オフにすると、以前リンクを開いていたアプリに戻ります。",
        actionLabel: "リンクをクリックしたとき",
        actionIgnore: "何もしない",
        actionOpenApp: "ほかのアプリで開く",
        actionCopy: "アドレスをコピー",
        appLabel: "アプリ",
        appNone: "なし",
        chooseApp: "アプリを選択…",
        appRejected: "“メール”はブロック対象のため、これらのリンクを開けません。ほかのアプリを選んでください。",
        unavailable: "現在メールのリンクを引き継げませんでした。オフにしてからもう一度オンにしてください。",
        copied: "メールアドレスをコピーしました"
    )

    static let ko = MailBlockStrings(
        hubTitle: "Mail 링크 차단",
        hubDescription: "이메일 링크가 Mail을 열지 않도록 막기",
        section: "이메일 링크",
        title: "이메일 링크로 Mail이 열리지 않게 하기",
        caption: "Vorssaint가 Mail 대신 이메일 링크를 받아 아래에서 선택한 동작을 합니다. 끄면 이전에 링크를 열던 앱으로 되돌립니다.",
        actionLabel: "링크를 클릭하면",
        actionIgnore: "아무것도 하지 않음",
        actionOpenApp: "다른 앱에서 열기",
        actionCopy: "주소 복사",
        appLabel: "앱",
        appNone: "없음",
        chooseApp: "앱 선택…",
        appRejected: "Mail은 차단 대상이므로 이 링크를 열 수 없습니다. 다른 앱을 선택하세요.",
        unavailable: "지금은 이메일 링크를 넘겨받지 못했습니다. 껐다가 다시 켜서 재시도하세요.",
        copied: "이메일 주소를 복사했습니다"
    )

    static let uk = MailBlockStrings(
        hubTitle: "Блокування посилань Пошти",
        hubDescription: "Не дає посиланням на e-mail відкривати Пошту",
        section: "Посилання на e-mail",
        title: "Не відкривати Пошту за посиланнями на e-mail",
        caption: "Vorssaint приймає посилання на e-mail замість Пошти й робить те, що вибрано нижче. Після вимкнення посилання повертаються програмі, яка відкривала їх раніше.",
        actionLabel: "Після натискання на посилання",
        actionIgnore: "Нічого не робити",
        actionOpenApp: "Відкрити в іншій програмі",
        actionCopy: "Скопіювати адресу",
        appLabel: "Програма",
        appNone: "Немає",
        chooseApp: "Вибрати програму…",
        appRejected: "Пошта саме блокується, тож не може відкривати ці посилання. Виберіть іншу програму.",
        unavailable: "Зараз не вдалося перехопити посилання на e-mail. Вимкніть і знову ввімкніть опцію, щоб повторити спробу.",
        copied: "Адресу e-mail скопійовано"
    )

    static let zhHans = MailBlockStrings(
        hubTitle: "“邮件”链接拦截",
        hubDescription: "阻止电子邮件链接打开“邮件”",
        section: "电子邮件链接",
        title: "阻止电子邮件链接打开“邮件”",
        caption: "Vorssaint 代替“邮件”接收电子邮件链接，并执行你在下方选择的操作。关闭后，链接会交还给之前打开它们的 App。",
        actionLabel: "点击链接时",
        actionIgnore: "不执行任何操作",
        actionOpenApp: "在其他 App 中打开",
        actionCopy: "拷贝地址",
        appLabel: "App",
        appNone: "无",
        chooseApp: "选择 App…",
        appRejected: "“邮件”正是被拦截的 App，因此不能打开这些链接。请选择其他 App。",
        unavailable: "目前无法接管电子邮件链接。请关闭后重新打开此选项再试。",
        copied: "已拷贝电子邮件地址"
    )

    static let zhTW = MailBlockStrings(
        hubTitle: "「郵件」連結攔截",
        hubDescription: "防止電子郵件連結打開「郵件」",
        section: "電子郵件連結",
        title: "防止電子郵件連結打開「郵件」",
        caption: "Vorssaint 會代替「郵件」接收電子郵件連結，並執行你在下方選擇的動作。關閉後，連結會交還給之前打開它們的 App。",
        actionLabel: "按一下連結時",
        actionIgnore: "不執行任何動作",
        actionOpenApp: "在其他 App 中打開",
        actionCopy: "拷貝位址",
        appLabel: "App",
        appNone: "無",
        chooseApp: "選擇 App⋯",
        appRejected: "「郵件」正是被攔截的 App，因此無法打開這些連結。請選擇其他 App。",
        unavailable: "目前無法接管電子郵件連結。請關閉後重新開啟此選項再試一次。",
        copied: "已拷貝電子郵件位址"
    )

    static let zhHK = MailBlockStrings(
        hubTitle: "「郵件」連結攔截",
        hubDescription: "防止電郵連結打開「郵件」",
        section: "電郵連結",
        title: "防止電郵連結打開「郵件」",
        caption: "Vorssaint 會代替「郵件」接收電郵連結，並執行你在下方選擇的動作。關閉後，連結會交還給之前打開它們的 App。",
        actionLabel: "按一下連結時",
        actionIgnore: "不執行任何動作",
        actionOpenApp: "在其他 App 中打開",
        actionCopy: "拷貝地址",
        appLabel: "App",
        appNone: "無",
        chooseApp: "選擇 App⋯",
        appRejected: "「郵件」正是被攔截的 App，因此無法打開這些連結。請選擇其他 App。",
        unavailable: "目前無法接管電郵連結。請關閉後重新開啟此選項再試一次。",
        copied: "已拷貝電郵地址"
    )
}
