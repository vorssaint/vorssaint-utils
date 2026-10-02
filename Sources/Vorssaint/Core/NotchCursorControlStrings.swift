// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCursorControlStrings {
    let allow: String
    let deny: String
    let alwaysAllow: String
    let answerInCursor: String
    let confirmRule: String
    let autoAllowed: String
    let autoDenied: String
    let queue: String
    let send: String
    let skip: String
    let holdHint: String
    let newChat: String
    let addFolder: String
    let promptTooLong: String
    let jump: String
    let openFile: String
    let signIn: String
    let ghMissing: String
    let createPR: String
    let merge: String
    let checks: String
    let draft: String
    let askCommit: String
    let remoteOff: String
    let contextNote: String
    let approvals: String
    let protectedPaths: String
    let allowRules: String
    let denyRules: String
    let sources: String
    let appOnly: String
    let appAndTerminal: String
    let pullRequests: String
    let deleteBranch: String

    func of(_ index: Int, _ count: Int) -> String { "\(index) / \(count)" }
    func tokens(_ command: String) -> String { CursorApprovalRules.tokens(command).joined(separator: " ") }
}

extension FeatureStrings {
    static func notchCursorControl(_ language: AppLanguage) -> NotchCursorControlStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NotchCursorControlStrings {
    static let enUS = NotchCursorControlStrings(
        allow: "Allow", deny: "Deny", alwaysAllow: "Always allow", answerInCursor: "Answer in Cursor",
        confirmRule: "Save this rule", autoAllowed: "Allowed by a rule", autoDenied: "Denied by a rule",
        queue: "Queue a reply", send: "Send", skip: "Skip",
        holdHint: "The agent waits until you send, skip, or the timer ends.",
        newChat: "New chat", addFolder: "Add folder", promptTooLong: "Too long for a Cursor link",
        jump: "Jump to window", openFile: "Open", signIn: "Sign in to GitHub CLI", ghMissing: "GitHub CLI is not installed",
        createPR: "Create PR", merge: "Merge", checks: "Checks", draft: "Draft",
        askCommit: "Ask the agent to commit", remoteOff: "Remote workspace",
        contextNote: "Context note", approvals: "Approvals", protectedPaths: "Protected paths",
        allowRules: "Allow rules", denyRules: "Deny rules", sources: "Sessions", appOnly: "App",
        appAndTerminal: "App and Terminal", pullRequests: "Pull requests", deleteBranch: "Delete branch"
    )
    static let ptBR = NotchCursorControlStrings(
        allow: "Permitir", deny: "Negar", alwaysAllow: "Sempre permitir", answerInCursor: "Responder no Cursor",
        confirmRule: "Salvar esta regra", autoAllowed: "Permitido por uma regra", autoDenied: "Negado por uma regra",
        queue: "Enfileirar uma resposta", send: "Enviar", skip: "Pular",
        holdHint: "O agente espera até você enviar, pular ou o tempo acabar.",
        newChat: "Novo chat", addFolder: "Adicionar pasta", promptTooLong: "Longo demais para um link do Cursor",
        jump: "Ir para a janela", openFile: "Abrir", signIn: "Entrar no GitHub CLI", ghMissing: "O GitHub CLI não está instalado",
        createPR: "Criar PR", merge: "Mesclar", checks: "Verificações", draft: "Rascunho",
        askCommit: "Pedir ao agente para fazer commit", remoteOff: "Área de trabalho remota",
        contextNote: "Nota de contexto", approvals: "Aprovações", protectedPaths: "Caminhos protegidos",
        allowRules: "Regras de permissão", denyRules: "Regras de negação", sources: "Sessões", appOnly: "App",
        appAndTerminal: "App e Terminal", pullRequests: "Pull requests", deleteBranch: "Apagar o branch"
    )
    static let es = NotchCursorControlStrings(
        allow: "Permitir", deny: "Denegar", alwaysAllow: "Permitir siempre", answerInCursor: "Responder en Cursor",
        confirmRule: "Guardar esta regla", autoAllowed: "Permitido por una regla", autoDenied: "Denegado por una regla",
        queue: "Poner una respuesta en cola", send: "Enviar", skip: "Omitir",
        holdHint: "El agente espera hasta que envíes, omitas o termine el tiempo.",
        newChat: "Nuevo chat", addFolder: "Añadir carpeta", promptTooLong: "Demasiado largo para un enlace de Cursor",
        jump: "Ir a la ventana", openFile: "Abrir", signIn: "Iniciar sesión en GitHub CLI", ghMissing: "GitHub CLI no está instalado",
        createPR: "Crear PR", merge: "Fusionar", checks: "Comprobaciones", draft: "Borrador",
        askCommit: "Pedir al agente que haga commit", remoteOff: "Espacio remoto",
        contextNote: "Nota de contexto", approvals: "Aprobaciones", protectedPaths: "Rutas protegidas",
        allowRules: "Reglas de permiso", denyRules: "Reglas de denegación", sources: "Sesiones", appOnly: "App",
        appAndTerminal: "App y Terminal", pullRequests: "Pull requests", deleteBranch: "Borrar la rama"
    )
    static let sk = NotchCursorControlStrings(
        allow: "Povoliť", deny: "Zamietnuť", alwaysAllow: "Vždy povoliť", answerInCursor: "Odpovedať v Cursor",
        confirmRule: "Uložiť toto pravidlo", autoAllowed: "Povolené pravidlom", autoDenied: "Zamietnuté pravidlom",
        queue: "Zaradiť odpoveď", send: "Odoslať", skip: "Preskočiť",
        holdHint: "Agent čaká, kým odošlete, preskočíte alebo vyprší čas.",
        newChat: "Nový chat", addFolder: "Pridať priečinok", promptTooLong: "Príliš dlhé na odkaz Cursor",
        jump: "Prejsť do okna", openFile: "Otvoriť", signIn: "Prihlásiť sa do GitHub CLI", ghMissing: "GitHub CLI nie je nainštalované",
        createPR: "Vytvoriť PR", merge: "Zlúčiť", checks: "Kontroly", draft: "Koncept",
        askCommit: "Požiadať agenta o commit", remoteOff: "Vzdialený priečinok",
        contextNote: "Kontextová poznámka", approvals: "Schválenia", protectedPaths: "Chránené cesty",
        allowRules: "Pravidlá povolenia", denyRules: "Pravidlá zamietnutia", sources: "Relácie", appOnly: "App",
        appAndTerminal: "App a terminál", pullRequests: "Pull requesty", deleteBranch: "Zmazať vetvu"
    )
    static let de = NotchCursorControlStrings(
        allow: "Erlauben", deny: "Ablehnen", alwaysAllow: "Immer erlauben", answerInCursor: "In Cursor antworten",
        confirmRule: "Diese Regel sichern", autoAllowed: "Durch eine Regel erlaubt", autoDenied: "Durch eine Regel abgelehnt",
        queue: "Antwort einreihen", send: "Senden", skip: "Überspringen",
        holdHint: "Der Agent wartet, bis du sendest, überspringst oder die Zeit endet.",
        newChat: "Neuer Chat", addFolder: "Ordner hinzufügen", promptTooLong: "Zu lang für einen Cursor-Link",
        jump: "Zum Fenster", openFile: "Öffnen", signIn: "Bei GitHub CLI anmelden", ghMissing: "GitHub CLI ist nicht installiert",
        createPR: "PR erstellen", merge: "Mergen", checks: "Checks", draft: "Entwurf",
        askCommit: "Den Agenten um einen Commit bitten", remoteOff: "Entfernter Arbeitsordner",
        contextNote: "Kontextnotiz", approvals: "Freigaben", protectedPaths: "Geschützte Pfade",
        allowRules: "Erlauben-Regeln", denyRules: "Ablehnen-Regeln", sources: "Sitzungen", appOnly: "App",
        appAndTerminal: "App und Terminal", pullRequests: "Pull Requests", deleteBranch: "Branch löschen"
    )
    static let fr = NotchCursorControlStrings(
        allow: "Autoriser", deny: "Refuser", alwaysAllow: "Toujours autoriser", answerInCursor: "Répondre dans Cursor",
        confirmRule: "Enregistrer cette règle", autoAllowed: "Autorisé par une règle", autoDenied: "Refusé par une règle",
        queue: "Mettre une réponse en file", send: "Envoyer", skip: "Passer",
        holdHint: "L’agent attend un envoi, un passage ou la fin du délai.",
        newChat: "Nouveau chat", addFolder: "Ajouter un dossier", promptTooLong: "Trop long pour un lien Cursor",
        jump: "Aller à la fenêtre", openFile: "Ouvrir", signIn: "Se connecter à GitHub CLI", ghMissing: "GitHub CLI n’est pas installé",
        createPR: "Créer une PR", merge: "Fusionner", checks: "Contrôles", draft: "Brouillon",
        askCommit: "Demander à l’agent de valider", remoteOff: "Dossier distant",
        contextNote: "Note de contexte", approvals: "Approbations", protectedPaths: "Chemins protégés",
        allowRules: "Règles d’autorisation", denyRules: "Règles de refus", sources: "Sessions", appOnly: "App",
        appAndTerminal: "App et Terminal", pullRequests: "Pull requests", deleteBranch: "Supprimer la branche"
    )
    static let it = NotchCursorControlStrings(
        allow: "Consenti", deny: "Nega", alwaysAllow: "Consenti sempre", answerInCursor: "Rispondi in Cursor",
        confirmRule: "Salva questa regola", autoAllowed: "Consentito da una regola", autoDenied: "Negato da una regola",
        queue: "Metti in coda una risposta", send: "Invia", skip: "Salta",
        holdHint: "L’agente attende un invio, un salto o la fine del tempo.",
        newChat: "Nuova chat", addFolder: "Aggiungi cartella", promptTooLong: "Troppo lungo per un link di Cursor",
        jump: "Vai alla finestra", openFile: "Apri", signIn: "Accedi a GitHub CLI", ghMissing: "GitHub CLI non è installato",
        createPR: "Crea PR", merge: "Unisci", checks: "Controlli", draft: "Bozza",
        askCommit: "Chiedi all’agente di fare commit", remoteOff: "Cartella remota",
        contextNote: "Nota di contesto", approvals: "Approvazioni", protectedPaths: "Percorsi protetti",
        allowRules: "Regole di consenso", denyRules: "Regole di negazione", sources: "Sessioni", appOnly: "App",
        appAndTerminal: "App e Terminale", pullRequests: "Pull request", deleteBranch: "Elimina il branch"
    )
    static let ru = NotchCursorControlStrings(
        allow: "Разрешить", deny: "Отклонить", alwaysAllow: "Всегда разрешать", answerInCursor: "Ответить в Cursor",
        confirmRule: "Сохранить это правило", autoAllowed: "Разрешено правилом", autoDenied: "Отклонено правилом",
        queue: "Поставить ответ в очередь", send: "Отправить", skip: "Пропустить",
        holdHint: "Агент ждёт отправки, пропуска или конца времени.",
        newChat: "Новый чат", addFolder: "Добавить папку", promptTooLong: "Слишком длинно для ссылки Cursor",
        jump: "К окну", openFile: "Открыть", signIn: "Войти в GitHub CLI", ghMissing: "GitHub CLI не установлен",
        createPR: "Создать PR", merge: "Слить", checks: "Проверки", draft: "Черновик",
        askCommit: "Попросить агента сделать коммит", remoteOff: "Удалённая папка",
        contextNote: "Заметка контекста", approvals: "Подтверждения", protectedPaths: "Защищённые пути",
        allowRules: "Правила разрешения", denyRules: "Правила отклонения", sources: "Сессии", appOnly: "Приложение",
        appAndTerminal: "Приложение и терминал", pullRequests: "Pull request", deleteBranch: "Удалить ветку"
    )
    static let tr = NotchCursorControlStrings(
        allow: "İzin ver", deny: "Reddet", alwaysAllow: "Her zaman izin ver", answerInCursor: "Cursor’da yanıtla",
        confirmRule: "Bu kuralı kaydet", autoAllowed: "Kural izin verdi", autoDenied: "Kural reddetti",
        queue: "Bir yanıt sıraya al", send: "Gönder", skip: "Geç",
        holdHint: "Aracı, gönderene, geçene veya süre bitene kadar bekler.",
        newChat: "Yeni sohbet", addFolder: "Klasör ekle", promptTooLong: "Cursor bağlantısı için çok uzun",
        jump: "Pencereye git", openFile: "Aç", signIn: "GitHub CLI’ye giriş yap", ghMissing: "GitHub CLI yüklü değil",
        createPR: "PR oluştur", merge: "Birleştir", checks: "Kontroller", draft: "Taslak",
        askCommit: "Aracıdan commit istemesi", remoteOff: "Uzak klasör",
        contextNote: "Bağlam notu", approvals: "Onaylar", protectedPaths: "Korunan yollar",
        allowRules: "İzin kuralları", denyRules: "Ret kuralları", sources: "Oturumlar", appOnly: "Uygulama",
        appAndTerminal: "Uygulama ve Terminal", pullRequests: "Pull request", deleteBranch: "Dalı sil"
    )
    static let ja = NotchCursorControlStrings(
        allow: "許可", deny: "拒否", alwaysAllow: "常に許可", answerInCursor: "Cursorで答える",
        confirmRule: "このルールを保存", autoAllowed: "ルールで許可", autoDenied: "ルールで拒否",
        queue: "返信を予約", send: "送信", skip: "スキップ",
        holdHint: "送信、スキップ、または時間切れまでエージェントは待ちます。",
        newChat: "新しいチャット", addFolder: "フォルダを追加", promptTooLong: "Cursorのリンクには長すぎます",
        jump: "ウィンドウへ", openFile: "開く", signIn: "GitHub CLIにサインイン", ghMissing: "GitHub CLIがありません",
        createPR: "PRを作成", merge: "マージ", checks: "チェック", draft: "下書き",
        askCommit: "エージェントにコミットを頼む", remoteOff: "リモートのフォルダ",
        contextNote: "コンテキストメモ", approvals: "承認", protectedPaths: "保護パス",
        allowRules: "許可ルール", denyRules: "拒否ルール", sources: "セッション", appOnly: "アプリ",
        appAndTerminal: "アプリとターミナル", pullRequests: "プルリクエスト", deleteBranch: "ブランチを削除"
    )
    static let ko = NotchCursorControlStrings(
        allow: "허용", deny: "거부", alwaysAllow: "항상 허용", answerInCursor: "Cursor에서 답하기",
        confirmRule: "이 규칙 저장", autoAllowed: "규칙으로 허용", autoDenied: "규칙으로 거부",
        queue: "답변을 대기열에 넣기", send: "보내기", skip: "건너뛰기",
        holdHint: "보내거나 건너뛰거나 시간이 끝날 때까지 에이전트가 기다립니다.",
        newChat: "새 채팅", addFolder: "폴더 추가", promptTooLong: "Cursor 링크에 너무 깁니다",
        jump: "창으로 이동", openFile: "열기", signIn: "GitHub CLI에 로그인", ghMissing: "GitHub CLI가 없습니다",
        createPR: "PR 만들기", merge: "병합", checks: "검사", draft: "초안",
        askCommit: "에이전트에게 커밋 요청", remoteOff: "원격 폴더",
        contextNote: "맥락 메모", approvals: "승인", protectedPaths: "보호 경로",
        allowRules: "허용 규칙", denyRules: "거부 규칙", sources: "세션", appOnly: "앱",
        appAndTerminal: "앱과 터미널", pullRequests: "풀 리퀘스트", deleteBranch: "브랜치 삭제"
    )
    static let uk = NotchCursorControlStrings(
        allow: "Дозволити", deny: "Відхилити", alwaysAllow: "Завжди дозволяти", answerInCursor: "Відповісти в Cursor",
        confirmRule: "Зберегти це правило", autoAllowed: "Дозволено правилом", autoDenied: "Відхилено правилом",
        queue: "Поставити відповідь у чергу", send: "Надіслати", skip: "Пропустити",
        holdHint: "Агент чекає на надсилання, пропуск або кінець часу.",
        newChat: "Новий чат", addFolder: "Додати теку", promptTooLong: "Задовге для посилання Cursor",
        jump: "До вікна", openFile: "Відкрити", signIn: "Увійти в GitHub CLI", ghMissing: "GitHub CLI не встановлено",
        createPR: "Створити PR", merge: "Злити", checks: "Перевірки", draft: "Чернетка",
        askCommit: "Попросити агента зробити коміт", remoteOff: "Віддалена тека",
        contextNote: "Нотатка контексту", approvals: "Підтвердження", protectedPaths: "Захищені шляхи",
        allowRules: "Правила дозволу", denyRules: "Правила відхилення", sources: "Сесії", appOnly: "Застосунок",
        appAndTerminal: "Застосунок і термінал", pullRequests: "Pull request", deleteBranch: "Видалити гілку"
    )
    static let zhHans = NotchCursorControlStrings(
        allow: "允许", deny: "拒绝", alwaysAllow: "始终允许", answerInCursor: "在 Cursor 中回答",
        confirmRule: "保存此规则", autoAllowed: "规则已允许", autoDenied: "规则已拒绝",
        queue: "排队一条回复", send: "发送", skip: "跳过",
        holdHint: "代理会等到你发送、跳过或时间结束。",
        newChat: "新对话", addFolder: "添加文件夹", promptTooLong: "超出 Cursor 链接长度",
        jump: "跳到窗口", openFile: "打开", signIn: "登录 GitHub CLI", ghMissing: "未安装 GitHub CLI",
        createPR: "创建 PR", merge: "合并", checks: "检查", draft: "草稿",
        askCommit: "请代理提交", remoteOff: "远程文件夹",
        contextNote: "上下文备注", approvals: "批准", protectedPaths: "受保护路径",
        allowRules: "允许规则", denyRules: "拒绝规则", sources: "会话", appOnly: "应用",
        appAndTerminal: "应用和终端", pullRequests: "拉取请求", deleteBranch: "删除分支"
    )
    static let zhTW = NotchCursorControlStrings(
        allow: "允許", deny: "拒絕", alwaysAllow: "一律允許", answerInCursor: "在 Cursor 中回答",
        confirmRule: "儲存此規則", autoAllowed: "規則已允許", autoDenied: "規則已拒絕",
        queue: "將回覆排入佇列", send: "送出", skip: "略過",
        holdHint: "代理會等到你送出、略過或時間結束。",
        newChat: "新對話", addFolder: "加入資料夾", promptTooLong: "超過 Cursor 連結長度",
        jump: "跳到視窗", openFile: "打開", signIn: "登入 GitHub CLI", ghMissing: "未安裝 GitHub CLI",
        createPR: "建立 PR", merge: "合併", checks: "檢查", draft: "草稿",
        askCommit: "請代理提交", remoteOff: "遠端資料夾",
        contextNote: "情境備註", approvals: "核准", protectedPaths: "受保護路徑",
        allowRules: "允許規則", denyRules: "拒絕規則", sources: "工作階段", appOnly: "App",
        appAndTerminal: "App 與終端機", pullRequests: "拉取請求", deleteBranch: "刪除分支"
    )
    static let zhHK = NotchCursorControlStrings(
        allow: "允許", deny: "拒絕", alwaysAllow: "一律允許", answerInCursor: "在 Cursor 中回答",
        confirmRule: "儲存此規則", autoAllowed: "規則已允許", autoDenied: "規則已拒絕",
        queue: "將回覆排入佇列", send: "送出", skip: "略過",
        holdHint: "代理會等到你送出、略過或時間結束。",
        newChat: "新對話", addFolder: "加入資料夾", promptTooLong: "超過 Cursor 連結長度",
        jump: "跳到視窗", openFile: "打開", signIn: "登入 GitHub CLI", ghMissing: "未安裝 GitHub CLI",
        createPR: "建立 PR", merge: "合併", checks: "檢查", draft: "草稿",
        askCommit: "請代理提交", remoteOff: "遠端資料夾",
        contextNote: "情境備註", approvals: "核准", protectedPaths: "受保護路徑",
        allowRules: "允許規則", denyRules: "拒絕規則", sources: "工作階段", appOnly: "App",
        appAndTerminal: "App 與終端機", pullRequests: "拉取請求", deleteBranch: "刪除分支"
    )
}

struct NotchCursorOptionStrings {
    let liveActivity: String
    let readout: String
    let stateWord: String
    let elapsedWord: String
    let projectWord: String
    let notices: String
    let finishNotice: String
    let failureNotice: String
    let quietFocused: String
    let timeout: String
    let handBack: String
    let openIsland: String
    let editApprovals: String
    let holdForReply: String
    let queueOnAbort: String
    let replies: String
    let refresh: String
    let risky: String
    let confirm: String
    let cancel: String
}

extension FeatureStrings {
    static func notchCursorOptions(_ language: AppLanguage) -> NotchCursorOptionStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NotchCursorOptionStrings {
    static let enUS = NotchCursorOptionStrings(
        liveActivity: "Live activity", readout: "Readout", stateWord: "State", elapsedWord: "Elapsed", projectWord: "Project", notices: "Notices",
        finishNotice: "When a turn finishes", failureNotice: "When a turn fails",
        quietFocused: "Stay quiet while Cursor is in front", timeout: "Timeout",
        handBack: "Hand back to Cursor", openIsland: "Open the island", editApprovals: "Approve edits",
        holdForReply: "Hold for a reply", queueOnAbort: "Send a queued reply after a stop",
        replies: "Replies", refresh: "Refresh", risky: "Risky", confirm: "Confirm", cancel: "Cancel"
    )
    static let ptBR = NotchCursorOptionStrings(
        liveActivity: "Atividade ao vivo", readout: "Leitura", stateWord: "Estado", elapsedWord: "Tempo", projectWord: "Projeto", notices: "Avisos",
        finishNotice: "Quando um turno termina", failureNotice: "Quando um turno falha",
        quietFocused: "Ficar quieto enquanto o Cursor está na frente", timeout: "Tempo limite",
        handBack: "Devolver ao Cursor", openIsland: "Abrir a ilha", editApprovals: "Aprovar edições",
        holdForReply: "Esperar uma resposta", queueOnAbort: "Enviar a resposta em fila após uma parada",
        replies: "Respostas", refresh: "Atualizar", risky: "Arriscado", confirm: "Confirmar", cancel: "Cancelar"
    )
    static let es = NotchCursorOptionStrings(
        liveActivity: "Actividad en vivo", readout: "Lectura", stateWord: "Estado", elapsedWord: "Tiempo", projectWord: "Proyecto", notices: "Avisos",
        finishNotice: "Cuando un turno termina", failureNotice: "Cuando un turno falla",
        quietFocused: "Quedarse en silencio mientras Cursor está delante", timeout: "Tiempo límite",
        handBack: "Devolver a Cursor", openIsland: "Abrir la isla", editApprovals: "Aprobar ediciones",
        holdForReply: "Esperar una respuesta", queueOnAbort: "Enviar la respuesta en cola tras una parada",
        replies: "Respuestas", refresh: "Actualizar", risky: "Arriesgado", confirm: "Confirmar", cancel: "Cancelar"
    )
    static let sk = NotchCursorOptionStrings(
        liveActivity: "Živá aktivita", readout: "Údaj", stateWord: "Stav", elapsedWord: "Čas", projectWord: "Projekt", notices: "Upozornenia",
        finishNotice: "Keď kolo skončí", failureNotice: "Keď kolo zlyhá",
        quietFocused: "Mlčať, kým je Cursor vpredu", timeout: "Časový limit",
        handBack: "Vrátiť do Cursor", openIsland: "Otvoriť ostrov", editApprovals: "Schvaľovať úpravy",
        holdForReply: "Počkať na odpoveď", queueOnAbort: "Po zastavení odoslať zaradenú odpoveď",
        replies: "Odpovede", refresh: "Obnoviť", risky: "Rizikové", confirm: "Potvrdiť", cancel: "Zrušiť"
    )
    static let de = NotchCursorOptionStrings(
        liveActivity: "Live-Aktivität", readout: "Anzeige", stateWord: "Status", elapsedWord: "Dauer", projectWord: "Projekt", notices: "Hinweise",
        finishNotice: "Wenn ein Zug endet", failureNotice: "Wenn ein Zug fehlschlägt",
        quietFocused: "Still bleiben, solange Cursor vorn ist", timeout: "Zeitlimit",
        handBack: "An Cursor zurückgeben", openIsland: "Die Insel öffnen", editApprovals: "Änderungen freigeben",
        holdForReply: "Auf eine Antwort warten", queueOnAbort: "Eine eingereihte Antwort nach einem Stop senden",
        replies: "Antworten", refresh: "Aktualisieren", risky: "Riskant", confirm: "Bestätigen", cancel: "Abbrechen"
    )
    static let fr = NotchCursorOptionStrings(
        liveActivity: "Activité en direct", readout: "Lecture", stateWord: "État", elapsedWord: "Durée", projectWord: "Projet", notices: "Avis",
        finishNotice: "Quand un tour se termine", failureNotice: "Quand un tour échoue",
        quietFocused: "Rester silencieux quand Cursor est devant", timeout: "Délai",
        handBack: "Rendre la main à Cursor", openIsland: "Ouvrir l’îlot", editApprovals: "Approuver les modifications",
        holdForReply: "Attendre une réponse", queueOnAbort: "Envoyer une réponse en file après un arrêt",
        replies: "Réponses", refresh: "Actualiser", risky: "Risqué", confirm: "Confirmer", cancel: "Annuler"
    )
    static let it = NotchCursorOptionStrings(
        liveActivity: "Attività dal vivo", readout: "Lettura", stateWord: "Stato", elapsedWord: "Tempo", projectWord: "Progetto", notices: "Avvisi",
        finishNotice: "Quando un turno finisce", failureNotice: "Quando un turno fallisce",
        quietFocused: "Restare in silenzio mentre Cursor è davanti", timeout: "Tempo limite",
        handBack: "Restituire a Cursor", openIsland: "Aprire l’isola", editApprovals: "Approvare le modifiche",
        holdForReply: "Attendere una risposta", queueOnAbort: "Inviare una risposta in coda dopo uno stop",
        replies: "Risposte", refresh: "Aggiorna", risky: "Rischioso", confirm: "Conferma", cancel: "Annulla"
    )
    static let ru = NotchCursorOptionStrings(
        liveActivity: "Живая активность", readout: "Показание", stateWord: "Состояние", elapsedWord: "Время", projectWord: "Проект", notices: "Уведомления",
        finishNotice: "Когда ход завершён", failureNotice: "Когда ход не удался",
        quietFocused: "Молчать, пока Cursor на переднем плане", timeout: "Тайм-аут",
        handBack: "Вернуть в Cursor", openIsland: "Открыть остров", editApprovals: "Подтверждать правки",
        holdForReply: "Ждать ответ", queueOnAbort: "Отправить ответ из очереди после остановки",
        replies: "Ответы", refresh: "Обновить", risky: "Рискованно", confirm: "Подтвердить", cancel: "Отмена"
    )
    static let tr = NotchCursorOptionStrings(
        liveActivity: "Canlı etkinlik", readout: "Okuma", stateWord: "Durum", elapsedWord: "Süre", projectWord: "Proje", notices: "Bildirimler",
        finishNotice: "Bir tur bitince", failureNotice: "Bir tur başarısız olunca",
        quietFocused: "Cursor öndeyken sessiz kal", timeout: "Zaman aşımı",
        handBack: "Cursor’a geri ver", openIsland: "Adayı aç", editApprovals: "Düzenlemeleri onayla",
        holdForReply: "Bir yanıt bekle", queueOnAbort: "Durdurmadan sonra sıradaki yanıtı gönder",
        replies: "Yanıtlar", refresh: "Yenile", risky: "Riskli", confirm: "Onayla", cancel: "Vazgeç"
    )
    static let ja = NotchCursorOptionStrings(
        liveActivity: "ライブ表示", readout: "表示", stateWord: "状態", elapsedWord: "経過", projectWord: "プロジェクト", notices: "通知",
        finishNotice: "ターンが終わったとき", failureNotice: "ターンが失敗したとき",
        quietFocused: "Cursorが前面のあいだは静かにする", timeout: "タイムアウト",
        handBack: "Cursorに戻す", openIsland: "アイランドを開く", editApprovals: "編集を承認",
        holdForReply: "返信を待つ", queueOnAbort: "停止のあと、予約した返信を送る",
        replies: "返信", refresh: "更新", risky: "危険", confirm: "確認", cancel: "キャンセル"
    )
    static let ko = NotchCursorOptionStrings(
        liveActivity: "실시간 활동", readout: "표시", stateWord: "상태", elapsedWord: "경과", projectWord: "프로젝트", notices: "알림",
        finishNotice: "턴이 끝날 때", failureNotice: "턴이 실패할 때",
        quietFocused: "Cursor가 앞에 있을 때 조용히", timeout: "시간 제한",
        handBack: "Cursor에 되돌리기", openIsland: "아일랜드 열기", editApprovals: "편집 승인",
        holdForReply: "답변을 기다리기", queueOnAbort: "중지 후 대기 중인 답변 보내기",
        replies: "답변", refresh: "새로고침", risky: "위험", confirm: "확인", cancel: "취소"
    )
    static let uk = NotchCursorOptionStrings(
        liveActivity: "Жива активність", readout: "Показ", stateWord: "Стан", elapsedWord: "Час", projectWord: "Проєкт", notices: "Сповіщення",
        finishNotice: "Коли хід завершено", failureNotice: "Коли хід не вдався",
        quietFocused: "Мовчати, поки Cursor на передньому плані", timeout: "Час очікування",
        handBack: "Повернути в Cursor", openIsland: "Відкрити острів", editApprovals: "Підтверджувати правки",
        holdForReply: "Чекати на відповідь", queueOnAbort: "Надіслати відповідь із черги після зупинки",
        replies: "Відповіді", refresh: "Оновити", risky: "Ризиковано", confirm: "Підтвердити", cancel: "Скасувати"
    )
    static let zhHans = NotchCursorOptionStrings(
        liveActivity: "实时活动", readout: "读数", stateWord: "状态", elapsedWord: "用时", projectWord: "项目", notices: "通知",
        finishNotice: "一轮结束时", failureNotice: "一轮失败时",
        quietFocused: "Cursor 在前台时保持安静", timeout: "超时",
        handBack: "交回 Cursor", openIsland: "打开灵动岛", editApprovals: "批准编辑",
        holdForReply: "等待回复", queueOnAbort: "停止后发送排队的回复",
        replies: "回复", refresh: "刷新", risky: "有风险", confirm: "确认", cancel: "取消"
    )
    static let zhTW = NotchCursorOptionStrings(
        liveActivity: "即時活動", readout: "讀數", stateWord: "狀態", elapsedWord: "用時", projectWord: "專案", notices: "通知",
        finishNotice: "一輪結束時", failureNotice: "一輪失敗時",
        quietFocused: "Cursor 在前景時保持安靜", timeout: "逾時",
        handBack: "交回 Cursor", openIsland: "打開動態島", editApprovals: "核准編輯",
        holdForReply: "等待回覆", queueOnAbort: "停止後送出佇列中的回覆",
        replies: "回覆", refresh: "重新整理", risky: "有風險", confirm: "確認", cancel: "取消"
    )
    static let zhHK = NotchCursorOptionStrings(
        liveActivity: "即時活動", readout: "讀數", stateWord: "狀態", elapsedWord: "用時", projectWord: "專案", notices: "通知",
        finishNotice: "一輪結束時", failureNotice: "一輪失敗時",
        quietFocused: "Cursor 在前景時保持安靜", timeout: "逾時",
        handBack: "交回 Cursor", openIsland: "打開動態島", editApprovals: "核准編輯",
        holdForReply: "等待回覆", queueOnAbort: "停止後送出佇列中的回覆",
        replies: "回覆", refresh: "重新整理", risky: "有風險", confirm: "確認", cancel: "取消"
    )
}

struct NotchCursorPolishStrings {
    let experimental: String
    let sendNow: String
    let stopRun: String
    let keepAll: String
    let undoAll: String
    let test: String
    let record: String
    let needsTrust: String
    let notFront: String
    let titleUnverified: String
    let severalWindows: String
    let noShortcut: String
    let remoteBlocked: String
    let confirmUndo: String
    let look: String
    let buddy: String
    let eyesFollow: String
    let glow: String
    let typewriter: String
    let sounds: String

    func message(_ block: CursorExperimentalBlock) -> String {
        switch block {
        case .remote: return remoteBlocked
        case .needsTrust: return needsTrust
        case .notFront: return notFront
        case .titleUnverified: return titleUnverified
        case .severalWindows: return severalWindows
        case .noShortcut: return noShortcut
        }
    }
}

extension FeatureStrings {
    static func notchCursorPolish(_ language: AppLanguage) -> NotchCursorPolishStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NotchCursorPolishStrings {
    static let enUS = NotchCursorPolishStrings(
        experimental: "Experimental controls", sendNow: "Send now", stopRun: "Stop", keepAll: "Keep all", undoAll: "Undo all",
        test: "Test", record: "Press a shortcut", needsTrust: "Accessibility is required",
        notFront: "Cursor is not the front app", titleUnverified: "The window title format is not verified, so this stays off",
        severalWindows: "More than one Cursor window matches", noShortcut: "No shortcut is set",
        remoteBlocked: "Unavailable for a remote workspace", confirmUndo: "Undo all changes from this turn",
        look: "Look", buddy: "Mascot", eyesFollow: "Eyes follow the pointer", glow: "Glow",
        typewriter: "Typewriter", sounds: "Sounds"
    )
    static let ptBR = NotchCursorPolishStrings(
        experimental: "Controles experimentais", sendNow: "Enviar agora", stopRun: "Parar", keepAll: "Manter tudo", undoAll: "Desfazer tudo",
        test: "Testar", record: "Pressione um atalho", needsTrust: "Acessibilidade é necessária",
        notFront: "O Cursor não é o app da frente", titleUnverified: "O formato do título da janela não foi verificado, então isto fica desligado",
        severalWindows: "Mais de uma janela do Cursor corresponde", noShortcut: "Nenhum atalho definido",
        remoteBlocked: "Indisponível em uma área remota", confirmUndo: "Desfazer todas as mudanças deste turno",
        look: "Aparência", buddy: "Mascote", eyesFollow: "Os olhos seguem o ponteiro", glow: "Brilho",
        typewriter: "Máquina de escrever", sounds: "Sons"
    )
    static let es = NotchCursorPolishStrings(
        experimental: "Controles experimentales", sendNow: "Enviar ahora", stopRun: "Detener", keepAll: "Conservar todo", undoAll: "Deshacer todo",
        test: "Probar", record: "Pulsa un atajo", needsTrust: "Se necesita Accesibilidad",
        notFront: "Cursor no es la app de delante", titleUnverified: "El formato del título de la ventana no está verificado, así que esto queda apagado",
        severalWindows: "Coincide más de una ventana de Cursor", noShortcut: "No hay un atajo",
        remoteBlocked: "No disponible en un espacio remoto", confirmUndo: "Deshacer todos los cambios de este turno",
        look: "Aspecto", buddy: "Mascota", eyesFollow: "Los ojos siguen el puntero", glow: "Brillo",
        typewriter: "Máquina de escribir", sounds: "Sonidos"
    )
    static let sk = NotchCursorPolishStrings(
        experimental: "Experimentálne ovládanie", sendNow: "Odoslať teraz", stopRun: "Zastaviť", keepAll: "Ponechať všetko", undoAll: "Vrátiť všetko",
        test: "Vyskúšať", record: "Stlačte skratku", needsTrust: "Vyžaduje sa prístupnosť",
        notFront: "Cursor nie je vpredu", titleUnverified: "Formát názvu okna nie je overený, takže toto zostáva vypnuté",
        severalWindows: "Zodpovedá viac ako jedno okno Cursor", noShortcut: "Skratka nie je nastavená",
        remoteBlocked: "Nedostupné pre vzdialený priečinok", confirmUndo: "Vrátiť všetky zmeny tohto kola",
        look: "Vzhľad", buddy: "Maskot", eyesFollow: "Oči sledujú ukazovateľ", glow: "Žiara",
        typewriter: "Písací stroj", sounds: "Zvuky"
    )
    static let de = NotchCursorPolishStrings(
        experimental: "Experimentelle Steuerung", sendNow: "Jetzt senden", stopRun: "Stopp", keepAll: "Alles behalten", undoAll: "Alles rückgängig",
        test: "Testen", record: "Kurzbefehl drücken", needsTrust: "Bedienungshilfen werden gebraucht",
        notFront: "Cursor ist nicht vorn", titleUnverified: "Das Fenstertitelformat ist nicht geprüft, darum bleibt das aus",
        severalWindows: "Mehr als ein Cursor-Fenster passt", noShortcut: "Kein Kurzbefehl gesetzt",
        remoteBlocked: "Für einen entfernten Ordner nicht verfügbar", confirmUndo: "Alle Änderungen dieses Zugs rückgängig machen",
        look: "Aussehen", buddy: "Maskottchen", eyesFollow: "Augen folgen dem Zeiger", glow: "Leuchten",
        typewriter: "Schreibmaschine", sounds: "Töne"
    )
    static let fr = NotchCursorPolishStrings(
        experimental: "Commandes expérimentales", sendNow: "Envoyer maintenant", stopRun: "Arrêter", keepAll: "Tout garder", undoAll: "Tout annuler",
        test: "Essayer", record: "Appuyez sur un raccourci", needsTrust: "L’accessibilité est requise",
        notFront: "Cursor n’est pas l’app au premier plan", titleUnverified: "Le format du titre de fenêtre n’est pas vérifié, donc ceci reste éteint",
        severalWindows: "Plus d’une fenêtre Cursor correspond", noShortcut: "Aucun raccourci",
        remoteBlocked: "Indisponible pour un dossier distant", confirmUndo: "Annuler tous les changements de ce tour",
        look: "Apparence", buddy: "Mascotte", eyesFollow: "Les yeux suivent le pointeur", glow: "Lueur",
        typewriter: "Machine à écrire", sounds: "Sons"
    )
    static let it = NotchCursorPolishStrings(
        experimental: "Controlli sperimentali", sendNow: "Invia ora", stopRun: "Ferma", keepAll: "Tieni tutto", undoAll: "Annulla tutto",
        test: "Prova", record: "Premi una scorciatoia", needsTrust: "Serve Accessibilità",
        notFront: "Cursor non è l’app in primo piano", titleUnverified: "Il formato del titolo della finestra non è verificato, quindi questo resta spento",
        severalWindows: "Corrisponde più di una finestra di Cursor", noShortcut: "Nessuna scorciatoia",
        remoteBlocked: "Non disponibile per una cartella remota", confirmUndo: "Annulla tutte le modifiche di questo turno",
        look: "Aspetto", buddy: "Mascotte", eyesFollow: "Gli occhi seguono il puntatore", glow: "Bagliore",
        typewriter: "Macchina da scrivere", sounds: "Suoni"
    )
    static let ru = NotchCursorPolishStrings(
        experimental: "Экспериментальное управление", sendNow: "Отправить сейчас", stopRun: "Стоп", keepAll: "Оставить всё", undoAll: "Отменить всё",
        test: "Проверить", record: "Нажмите сочетание", needsTrust: "Нужен доступ Универсальный доступ",
        notFront: "Cursor не на переднем плане", titleUnverified: "Формат заголовка окна не проверен, поэтому это выключено",
        severalWindows: "Подходит больше одного окна Cursor", noShortcut: "Сочетание не задано",
        remoteBlocked: "Недоступно для удалённой папки", confirmUndo: "Отменить все изменения этого хода",
        look: "Вид", buddy: "Маскот", eyesFollow: "Глаза следят за указателем", glow: "Свечение",
        typewriter: "Печатная машинка", sounds: "Звуки"
    )
    static let tr = NotchCursorPolishStrings(
        experimental: "Deneysel denetimler", sendNow: "Şimdi gönder", stopRun: "Durdur", keepAll: "Tümünü tut", undoAll: "Tümünü geri al",
        test: "Dene", record: "Bir kısayola basın", needsTrust: "Erişilebilirlik gerekli",
        notFront: "Cursor önde değil", titleUnverified: "Pencere başlığı biçimi doğrulanmadı, bu yüzden bu kapalı kalır",
        severalWindows: "Birden fazla Cursor penceresi eşleşiyor", noShortcut: "Kısayol yok",
        remoteBlocked: "Uzak klasör için kullanılamaz", confirmUndo: "Bu turun tüm değişikliklerini geri al",
        look: "Görünüm", buddy: "Maskot", eyesFollow: "Gözler imleci izler", glow: "Parlama",
        typewriter: "Daktilo", sounds: "Sesler"
    )
    static let ja = NotchCursorPolishStrings(
        experimental: "実験的な操作", sendNow: "今すぐ送る", stopRun: "停止", keepAll: "すべて残す", undoAll: "すべて元に戻す",
        test: "テスト", record: "ショートカットを押す", needsTrust: "アクセシビリティが必要です",
        notFront: "Cursorが前面にありません", titleUnverified: "ウィンドウタイトルの形式が未確認なので、これはオフのままです",
        severalWindows: "複数のCursorウィンドウが一致します", noShortcut: "ショートカットがありません",
        remoteBlocked: "リモートのフォルダでは使えません", confirmUndo: "このターンの変更をすべて元に戻す",
        look: "見た目", buddy: "マスコット", eyesFollow: "目がポインタを追う", glow: "光",
        typewriter: "タイプライター", sounds: "音"
    )
    static let ko = NotchCursorPolishStrings(
        experimental: "실험적 제어", sendNow: "지금 보내기", stopRun: "중지", keepAll: "모두 유지", undoAll: "모두 실행 취소",
        test: "테스트", record: "단축키를 누르세요", needsTrust: "손쉬운 사용이 필요합니다",
        notFront: "Cursor가 앞에 없습니다", titleUnverified: "창 제목 형식이 확인되지 않아 이것은 꺼진 채로 있습니다",
        severalWindows: "Cursor 창이 둘 이상 일치합니다", noShortcut: "단축키가 없습니다",
        remoteBlocked: "원격 폴더에서는 사용할 수 없습니다", confirmUndo: "이 턴의 변경을 모두 실행 취소",
        look: "모양", buddy: "마스코트", eyesFollow: "눈이 포인터를 따라감", glow: "빛",
        typewriter: "타자기", sounds: "소리"
    )
    static let uk = NotchCursorPolishStrings(
        experimental: "Експериментальне керування", sendNow: "Надіслати зараз", stopRun: "Зупинити", keepAll: "Залишити все", undoAll: "Скасувати все",
        test: "Перевірити", record: "Натисніть скорочення", needsTrust: "Потрібен універсальний доступ",
        notFront: "Cursor не на передньому плані", titleUnverified: "Формат заголовка вікна не перевірено, тож це лишається вимкненим",
        severalWindows: "Підходить більше одного вікна Cursor", noShortcut: "Скорочення не задано",
        remoteBlocked: "Недоступно для віддаленої теки", confirmUndo: "Скасувати всі зміни цього ходу",
        look: "Вигляд", buddy: "Маскот", eyesFollow: "Очі стежать за вказівником", glow: "Світіння",
        typewriter: "Друкарська машинка", sounds: "Звуки"
    )
    static let zhHans = NotchCursorPolishStrings(
        experimental: "实验性控制", sendNow: "立即发送", stopRun: "停止", keepAll: "全部保留", undoAll: "全部撤销",
        test: "测试", record: "按下快捷键", needsTrust: "需要辅助功能",
        notFront: "Cursor 不在前面", titleUnverified: "窗口标题格式尚未核实，因此这项保持关闭",
        severalWindows: "匹配到多个 Cursor 窗口", noShortcut: "没有快捷键",
        remoteBlocked: "远程文件夹不可用", confirmUndo: "撤销这一轮的全部更改",
        look: "外观", buddy: "吉祥物", eyesFollow: "眼睛跟随指针", glow: "光晕",
        typewriter: "打字机", sounds: "声音"
    )
    static let zhTW = NotchCursorPolishStrings(
        experimental: "實驗性控制", sendNow: "立即送出", stopRun: "停止", keepAll: "全部保留", undoAll: "全部還原",
        test: "測試", record: "按下快捷鍵", needsTrust: "需要輔助使用",
        notFront: "Cursor 不在前景", titleUnverified: "視窗標題格式尚未核實，因此這項保持關閉",
        severalWindows: "符合的 Cursor 視窗超過一個", noShortcut: "沒有快捷鍵",
        remoteBlocked: "遠端資料夾無法使用", confirmUndo: "還原這一輪的全部更改",
        look: "外觀", buddy: "吉祥物", eyesFollow: "眼睛跟隨指標", glow: "光暈",
        typewriter: "打字機", sounds: "聲音"
    )
    static let zhHK = NotchCursorPolishStrings(
        experimental: "實驗性控制", sendNow: "立即送出", stopRun: "停止", keepAll: "全部保留", undoAll: "全部還原",
        test: "測試", record: "按下快捷鍵", needsTrust: "需要輔助使用",
        notFront: "Cursor 不在前景", titleUnverified: "視窗標題格式尚未核實，因此這項保持關閉",
        severalWindows: "符合的 Cursor 視窗超過一個", noShortcut: "沒有快捷鍵",
        remoteBlocked: "遠端資料夾無法使用", confirmUndo: "還原這一輪的全部更改",
        look: "外觀", buddy: "吉祥物", eyesFollow: "眼睛跟隨指標", glow: "光暈",
        typewriter: "打字機", sounds: "聲音"
    )
}
