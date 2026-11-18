// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The AI section’s words for a session waiting on its person.
struct AgentInputStrings {
    let needsYou: String
    let needYouFormat: String
    let noticeTitleFormat: String
    let question: String
    let permission: String
    let waitingFormat: String
    let settingTitle: String
    let settingCaption: String
    let connected: String
    let notConnected: String
    let unreadable: String
    let setUp: String
    let remove: String
    let setupCaption: String
    let setupFailed: String
    let alertTitle: String

    /// "Needs you" for one waiting session, "2 need you" for more.
    func waiting(count: Int) -> String {
        count > 1 ? String(format: needYouFormat, count) : needsYou
    }

    func noticeTitle(_ agent: String) -> String { String(format: noticeTitleFormat, agent) }

    func reason(_ reason: AgentInputRequest.Reason) -> String {
        reason == .permission ? permission : question
    }

    func waitingFor(_ duration: String) -> String { String(format: waitingFormat, duration) }
}

extension FeatureStrings {
    static func agentInput(_ language: AppLanguage) -> AgentInputStrings {
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
        case .zhHK: return .zhHK
        case .zhTW: return .zhTW
        }
    }
}

private extension AgentInputStrings {
    static let enUS = AgentInputStrings(
        needsYou: "Needs you",
        needYouFormat: "%d need you",
        noticeTitleFormat: "%@ needs you",
        question: "Question",
        permission: "Permission",
        waitingFormat: "waiting %@",
        settingTitle: "Show when Claude needs you",
        settingCaption: "A question mark and \"Needs you\" while Claude Code waits for an answer or a permission.",
        connected: "Connected to Claude Code",
        notConnected: "Claude Code isn’t connected",
        unreadable: "Claude Code’s settings file couldn’t be read",
        setUp: "Set up",
        remove: "Remove",
        setupCaption: "Set up adds a small hook to Claude Code’s settings so it can tell Vorssaint when it’s waiting. It only shares the session, the reason and the time, never your messages. A backup of the settings is kept.",
        setupFailed: "Couldn’t change Claude Code’s settings.",
        alertTitle: "When Claude needs you"
    )

    static let ptBR = AgentInputStrings(
        needsYou: "Precisa de você",
        needYouFormat: "%d precisam de você",
        noticeTitleFormat: "%@ precisa de você",
        question: "Pergunta",
        permission: "Permissão",
        waitingFormat: "aguardando há %@",
        settingTitle: "Mostrar quando o Claude precisar de você",
        settingCaption: "Um ponto de interrogação e “Precisa de você” enquanto o Claude Code aguarda uma resposta ou uma permissão.",
        connected: "Conectado ao Claude Code",
        notConnected: "O Claude Code não está conectado",
        unreadable: "Não foi possível ler os ajustes do Claude Code",
        setUp: "Configurar",
        remove: "Remover",
        setupCaption: "Configurar adiciona um pequeno hook aos ajustes do Claude Code para que ele avise o Vorssaint quando estiver aguardando. Só compartilha a sessão, o motivo e a hora, nunca suas mensagens. Uma cópia de segurança dos ajustes é mantida.",
        setupFailed: "Não foi possível alterar os ajustes do Claude Code.",
        alertTitle: "Quando o Claude precisar de você"
    )

    static let tr = AgentInputStrings(
        needsYou: "Seni bekliyor",
        needYouFormat: "%d seni bekliyor",
        noticeTitleFormat: "%@ seni bekliyor",
        question: "Soru",
        permission: "İzin",
        waitingFormat: "%@ bekliyor",
        settingTitle: "Claude seni beklediğinde göster",
        settingCaption: "Claude Code bir yanıt veya izin beklerken bir soru işareti ve “Seni bekliyor”.",
        connected: "Claude Code’a bağlı",
        notConnected: "Claude Code bağlı değil",
        unreadable: "Claude Code ayar dosyası okunamadı",
        setUp: "Kur",
        remove: "Kaldır",
        setupCaption: "Kur, Claude Code ayarlarına küçük bir hook ekler; böylece beklerken Vorssaint’e haber verir. Yalnızca oturumu, nedeni ve saati paylaşır, mesajlarını asla. Ayarların bir yedeği saklanır.",
        setupFailed: "Claude Code ayarları değiştirilemedi.",
        alertTitle: "Claude seni beklediğinde"
    )

    static let ru = AgentInputStrings(
        needsYou: "Ждёт вас",
        needYouFormat: "Ждут вас: %d",
        noticeTitleFormat: "%@ ждёт вас",
        question: "Вопрос",
        permission: "Разрешение",
        waitingFormat: "ждёт %@",
        settingTitle: "Показывать, когда Claude ждёт вас",
        settingCaption: "Вопросительный знак и «Ждёт вас», пока Claude Code ждёт ответа или разрешения.",
        connected: "Подключено к Claude Code",
        notConnected: "Claude Code не подключён",
        unreadable: "Не удалось прочитать настройки Claude Code",
        setUp: "Настроить",
        remove: "Удалить",
        setupCaption: "«Настроить» добавляет в настройки Claude Code небольшой хук, чтобы он сообщал Vorssaint, когда ждёт. Передаются только сеанс, причина и время, но не ваши сообщения. Резервная копия настроек сохраняется.",
        setupFailed: "Не удалось изменить настройки Claude Code.",
        alertTitle: "Когда Claude ждёт вас"
    )

    static let es = AgentInputStrings(
        needsYou: "Te necesita",
        needYouFormat: "%d te necesitan",
        noticeTitleFormat: "%@ te necesita",
        question: "Pregunta",
        permission: "Permiso",
        waitingFormat: "esperando %@",
        settingTitle: "Mostrar cuando Claude te necesite",
        settingCaption: "Un signo de interrogación y «Te necesita» mientras Claude Code espera una respuesta o un permiso.",
        connected: "Conectado a Claude Code",
        notConnected: "Claude Code no está conectado",
        unreadable: "No se pudo leer el archivo de ajustes de Claude Code",
        setUp: "Configurar",
        remove: "Quitar",
        setupCaption: "Configurar añade un pequeño hook a los ajustes de Claude Code para que avise a Vorssaint cuando esté esperando. Solo comparte la sesión, el motivo y la hora, nunca tus mensajes. Se guarda una copia de seguridad de los ajustes.",
        setupFailed: "No se pudieron cambiar los ajustes de Claude Code.",
        alertTitle: "Cuando Claude te necesite"
    )

    static let sk = AgentInputStrings(
        needsYou: "Potrebuje vás",
        needYouFormat: "Potrebujú vás: %d",
        noticeTitleFormat: "%@ vás potrebuje",
        question: "Otázka",
        permission: "Povolenie",
        waitingFormat: "čaká %@",
        settingTitle: "Zobraziť, keď vás Claude potrebuje",
        settingCaption: "Otáznik a „Potrebuje vás“, kým Claude Code čaká na odpoveď alebo povolenie.",
        connected: "Pripojené ku Claude Code",
        notConnected: "Claude Code nie je pripojený",
        unreadable: "Nastavenia Claude Code sa nepodarilo prečítať",
        setUp: "Nastaviť",
        remove: "Odstrániť",
        setupCaption: "Nastaviť pridá do nastavení Claude Code malý hook, aby dal Vorssaintu vedieť, keď čaká. Zdieľa len reláciu, dôvod a čas, nikdy vaše správy. Záloha nastavení sa uchová.",
        setupFailed: "Nastavenia Claude Code sa nepodarilo zmeniť.",
        alertTitle: "Keď vás Claude potrebuje"
    )

    static let de = AgentInputStrings(
        needsYou: "Braucht dich",
        needYouFormat: "%d brauchen dich",
        noticeTitleFormat: "%@ braucht dich",
        question: "Frage",
        permission: "Erlaubnis",
        waitingFormat: "wartet seit %@",
        settingTitle: "Zeigen, wenn Claude dich braucht",
        settingCaption: "Ein Fragezeichen und „Braucht dich“, während Claude Code auf eine Antwort oder eine Erlaubnis wartet.",
        connected: "Mit Claude Code verbunden",
        notConnected: "Claude Code ist nicht verbunden",
        unreadable: "Die Einstellungen von Claude Code konnten nicht gelesen werden",
        setUp: "Einrichten",
        remove: "Entfernen",
        setupCaption: "Einrichten fügt den Einstellungen von Claude Code einen kleinen Hook hinzu, damit es Vorssaint mitteilt, wenn es wartet. Geteilt werden nur Sitzung, Grund und Uhrzeit, nie deine Nachrichten. Eine Sicherung der Einstellungen wird behalten.",
        setupFailed: "Die Einstellungen von Claude Code konnten nicht geändert werden.",
        alertTitle: "Wenn Claude dich braucht"
    )

    static let fr = AgentInputStrings(
        needsYou: "A besoin de vous",
        needYouFormat: "%d ont besoin de vous",
        noticeTitleFormat: "%@ a besoin de vous",
        question: "Question",
        permission: "Autorisation",
        waitingFormat: "en attente depuis %@",
        settingTitle: "Afficher quand Claude a besoin de vous",
        settingCaption: "Un point d’interrogation et «\u{00A0}A besoin de vous\u{00A0}» pendant que Claude Code attend une réponse ou une autorisation.",
        connected: "Connecté à Claude Code",
        notConnected: "Claude Code n’est pas connecté",
        unreadable: "Impossible de lire les réglages de Claude Code",
        setUp: "Configurer",
        remove: "Retirer",
        setupCaption: "Configurer ajoute un petit hook aux réglages de Claude Code pour qu’il prévienne Vorssaint quand il attend. Seuls la session, le motif et l’heure sont partagés, jamais vos messages. Une copie de sauvegarde des réglages est conservée.",
        setupFailed: "Impossible de modifier les réglages de Claude Code.",
        alertTitle: "Quand Claude a besoin de vous"
    )

    static let it = AgentInputStrings(
        needsYou: "Ha bisogno di te",
        needYouFormat: "%d hanno bisogno di te",
        noticeTitleFormat: "%@ ha bisogno di te",
        question: "Domanda",
        permission: "Autorizzazione",
        waitingFormat: "in attesa da %@",
        settingTitle: "Mostra quando Claude ha bisogno di te",
        settingCaption: "Un punto interrogativo e «Ha bisogno di te» mentre Claude Code attende una risposta o un’autorizzazione.",
        connected: "Collegato a Claude Code",
        notConnected: "Claude Code non è collegato",
        unreadable: "Impossibile leggere le impostazioni di Claude Code",
        setUp: "Configura",
        remove: "Rimuovi",
        setupCaption: "Configura aggiunge un piccolo hook alle impostazioni di Claude Code perché avvisi Vorssaint quando è in attesa. Condivide solo la sessione, il motivo e l’ora, mai i tuoi messaggi. Viene conservata una copia di sicurezza delle impostazioni.",
        setupFailed: "Impossibile modificare le impostazioni di Claude Code.",
        alertTitle: "Quando Claude ha bisogno di te"
    )

    static let ja = AgentInputStrings(
        needsYou: "対応待ち",
        needYouFormat: "%d件の対応待ち",
        noticeTitleFormat: "%@が対応を待っています",
        question: "質問",
        permission: "許可",
        waitingFormat: "待機 %@",
        settingTitle: "Claudeが対応を待っているときに表示",
        settingCaption: "Claude Codeが回答や許可を待っている間、疑問符と「対応待ち」を表示します。",
        connected: "Claude Codeに接続済み",
        notConnected: "Claude Codeに接続されていません",
        unreadable: "Claude Codeの設定ファイルを読み込めませんでした",
        setUp: "設定",
        remove: "削除",
        setupCaption: "設定すると、待機中であることをVorssaintに知らせる小さなフックをClaude Codeの設定に追加します。共有するのはセッション、理由、時刻のみで、メッセージは共有しません。設定のバックアップを保存します。",
        setupFailed: "Claude Codeの設定を変更できませんでした。",
        alertTitle: "Claudeが対応を待っているとき"
    )

    static let ko = AgentInputStrings(
        needsYou: "응답 필요",
        needYouFormat: "%d개 응답 필요",
        noticeTitleFormat: "%@이(가) 응답을 기다림",
        question: "질문",
        permission: "권한",
        waitingFormat: "%@ 대기 중",
        settingTitle: "Claude가 응답을 기다릴 때 표시",
        settingCaption: "Claude Code가 답변이나 권한을 기다리는 동안 물음표와 “응답 필요”를 표시합니다.",
        connected: "Claude Code에 연결됨",
        notConnected: "Claude Code가 연결되지 않음",
        unreadable: "Claude Code 설정 파일을 읽을 수 없음",
        setUp: "설정",
        remove: "제거",
        setupCaption: "설정하면 Claude Code 설정에 작은 훅을 추가해 대기 중일 때 Vorssaint에 알립니다. 세션, 이유, 시간만 공유하며 메시지는 공유하지 않습니다. 설정 백업이 보관됩니다.",
        setupFailed: "Claude Code 설정을 변경할 수 없습니다.",
        alertTitle: "Claude가 응답을 기다릴 때"
    )

    static let uk = AgentInputStrings(
        needsYou: "Чекає на вас",
        needYouFormat: "Чекають на вас: %d",
        noticeTitleFormat: "%@ чекає на вас",
        question: "Питання",
        permission: "Дозвіл",
        waitingFormat: "чекає %@",
        settingTitle: "Показувати, коли Claude чекає на вас",
        settingCaption: "Знак питання і «Чекає на вас», поки Claude Code чекає на відповідь або дозвіл.",
        connected: "Під’єднано до Claude Code",
        notConnected: "Claude Code не під’єднано",
        unreadable: "Не вдалося прочитати налаштування Claude Code",
        setUp: "Налаштувати",
        remove: "Вилучити",
        setupCaption: "«Налаштувати» додає до налаштувань Claude Code невеликий хук, щоб він повідомляв Vorssaint, коли чекає. Передаються лише сеанс, причина й час, але не ваші повідомлення. Резервна копія налаштувань зберігається.",
        setupFailed: "Не вдалося змінити налаштування Claude Code.",
        alertTitle: "Коли Claude чекає на вас"
    )

    static let zhHans = AgentInputStrings(
        needsYou: "需要你",
        needYouFormat: "%d 个需要你",
        noticeTitleFormat: "%@ 需要你",
        question: "问题",
        permission: "权限",
        waitingFormat: "已等待 %@",
        settingTitle: "Claude 需要你时显示",
        settingCaption: "Claude Code 等待回复或权限时，显示问号和“需要你”。",
        connected: "已连接 Claude Code",
        notConnected: "未连接 Claude Code",
        unreadable: "无法读取 Claude Code 的设置文件",
        setUp: "设置",
        remove: "移除",
        setupCaption: "设置会在 Claude Code 的设置中添加一个小钩子，让它在等待时通知 Vorssaint。只共享会话、原因和时间，绝不共享你的消息。会保留一份设置备份。",
        setupFailed: "无法更改 Claude Code 的设置。",
        alertTitle: "Claude 需要你时"
    )

    static let zhHK = AgentInputStrings(
        needsYou: "需要你",
        needYouFormat: "%d 個需要你",
        noticeTitleFormat: "%@ 需要你",
        question: "問題",
        permission: "權限",
        waitingFormat: "已等候 %@",
        settingTitle: "Claude 需要你時顯示",
        settingCaption: "Claude Code 等候回覆或權限時，顯示問號和「需要你」。",
        connected: "已連接 Claude Code",
        notConnected: "未連接 Claude Code",
        unreadable: "無法讀取 Claude Code 的設定檔",
        setUp: "設定",
        remove: "移除",
        setupCaption: "設定會在 Claude Code 的設定中加入一個小鈎子，讓它在等候時通知 Vorssaint。只分享工作階段、原因和時間，絕不分享你的訊息。會保留一份設定備份。",
        setupFailed: "無法更改 Claude Code 的設定。",
        alertTitle: "Claude 需要你時"
    )

    static let zhTW = AgentInputStrings(
        needsYou: "需要你",
        needYouFormat: "%d 個需要你",
        noticeTitleFormat: "%@ 需要你",
        question: "問題",
        permission: "權限",
        waitingFormat: "已等待 %@",
        settingTitle: "Claude 需要你時顯示",
        settingCaption: "Claude Code 等待回覆或權限時，顯示問號和「需要你」。",
        connected: "已連線 Claude Code",
        notConnected: "未連線 Claude Code",
        unreadable: "無法讀取 Claude Code 的設定檔",
        setUp: "設定",
        remove: "移除",
        setupCaption: "設定會在 Claude Code 的設定中加入一個小掛鉤，讓它在等待時通知 Vorssaint。只分享工作階段、原因和時間，絕不分享你的訊息。會保留一份設定備份。",
        setupFailed: "無法變更 Claude Code 的設定。",
        alertTitle: "Claude 需要你時"
    )
}
