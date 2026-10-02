// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCursorViewStrings {
    let idle: String
    let sent: String
    let thinking: String
    let reading: String
    let searching: String
    let editing: String
    let running: String
    let waiting: String
    let subagent: String
    let done: String
    let stopped: String
    let failed: String
    let quiet: String
    let app: String
    let terminal: String
    let remote: String
    let background: String
    let timeline: String
    let edits: String
    let thinkingTitle: String
    let reply: String
    let showMore: String
    let sandbox: String
    let truncated: String
    let denied: String
    let readWord: String
    let searchWord: String
    let editWord: String
    let runWord: String
    let deleteWord: String
    let mcpWord: String
    let subagentWord: String
    let filesWord: String
    let commandsWord: String
    let failuresWord: String
    let finishedWord: String
    let failedWord: String
    let needsYouWord: String
    let inWord: String
    let outWord: String
    let cacheReadWord: String
    let cacheWriteWord: String

    func stateName(_ state: CursorLiveState) -> String {
        switch state {
        case .idle: return idle
        case .sent: return sent
        case .thinking: return thinking
        case .reading: return reading
        case .searching: return searching
        case .editing: return editing
        case .running: return running
        case .waiting: return waiting
        case .subagent: return subagent
        case .done: return done
        case .stopped: return stopped
        case .failed: return failed
        case .quiet: return quiet
        }
    }

    func step(_ label: CursorStepLabel, status: CursorStepStatus) -> String {
        let body: String
        switch label {
        case .read(let file): body = "\(readWord) \(file)"
        case .search(let query): body = "\(searchWord) \(query)"
        case .edit(let file): body = "\(editWord) \(file)"
        case .delete(let file): body = "\(deleteWord) \(file)"
        case .run(let command): body = "\(runWord) \(command)"
        case .mcp(let server, let tool):
            let name = [server, tool].filter { !$0.isEmpty }.joined(separator: ".")
            body = "\(mcpWord) \(name)"
        case .subagent(let task): body = "\(subagentWord) \(task)"
        case .tool(let name): body = name
        }
        switch status {
        case .running, .done: return body
        case .stopped: return "\(body) · \(stopped)"
        case .denied: return "\(body) · \(denied)"
        case .failed: return "\(body) · \(failed)"
        }
    }

    func summary(files: Int, commands: Int, failures: Int) -> String {
        "\(files) \(filesWord) · \(commands) \(commandsWord) · \(failures) \(failuresWord)"
    }

    func finished(_ project: String) -> String { "\(finishedWord) · \(project)" }
    func failed(_ project: String) -> String { "\(failedWord) · \(project)" }
    func needsYou(_ count: Int) -> String { "\(needsYouWord) · \(count)" }

    func tokens(_ counts: CursorTokenCounts) -> String {
        var parts: [String] = []
        if let input = counts.input { parts.append("\(inWord) \(input)") }
        if let output = counts.output { parts.append("\(outWord) \(output)") }
        if let cacheRead = counts.cacheRead { parts.append("\(cacheReadWord) \(cacheRead)") }
        if let cacheWrite = counts.cacheWrite { parts.append("\(cacheWriteWord) \(cacheWrite)") }
        return parts.joined(separator: " · ")
    }
}

extension FeatureStrings {
    static func notchCursorView(_ language: AppLanguage) -> NotchCursorViewStrings {
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

extension NotchCursorViewStrings {
    static let enUS = NotchCursorViewStrings(
        idle: "Idle", sent: "Sent", thinking: "Thinking", reading: "Reading", searching: "Searching",
        editing: "Editing", running: "Running", waiting: "Waiting", subagent: "Subagent", done: "Done",
        stopped: "Stopped", failed: "Failed", quiet: "Quiet", app: "App", terminal: "Terminal",
        remote: "Remote", background: "Background", timeline: "Timeline", edits: "Edits",
        thinkingTitle: "Thinking", reply: "Reply", showMore: "Show more", sandbox: "Sandbox",
        truncated: "Truncated", denied: "Denied", readWord: "Read", searchWord: "Search", editWord: "Edit",
        runWord: "Run", deleteWord: "Delete", mcpWord: "MCP", subagentWord: "Subagent", filesWord: "files",
        commandsWord: "commands", failuresWord: "failures", finishedWord: "Finished", failedWord: "Failed",
        needsYouWord: "Needs you", inWord: "in", outWord: "out", cacheReadWord: "cache read",
        cacheWriteWord: "cache write"
    )
    static let ptBR = NotchCursorViewStrings(
        idle: "Ocioso", sent: "Enviado", thinking: "Pensando", reading: "Lendo", searching: "Buscando",
        editing: "Editando", running: "Executando", waiting: "Aguardando", subagent: "Subagente",
        done: "Concluído", stopped: "Interrompido", failed: "Falhou", quiet: "Quieto", app: "App",
        terminal: "Terminal", remote: "Remoto", background: "Segundo plano", timeline: "Linha do tempo",
        edits: "Edições", thinkingTitle: "Pensando", reply: "Resposta", showMore: "Mostrar mais",
        sandbox: "Sandbox", truncated: "Cortado", denied: "Negado", readWord: "Ler", searchWord: "Buscar",
        editWord: "Editar", runWord: "Executar", deleteWord: "Apagar", mcpWord: "MCP",
        subagentWord: "Subagente", filesWord: "arquivos", commandsWord: "comandos", failuresWord: "falhas",
        finishedWord: "Concluído", failedWord: "Falhou", needsYouWord: "Precisa de você", inWord: "entrada",
        outWord: "saída", cacheReadWord: "cache lido", cacheWriteWord: "cache escrito"
    )
    static let es = NotchCursorViewStrings(
        idle: "Inactivo", sent: "Enviado", thinking: "Pensando", reading: "Leyendo", searching: "Buscando",
        editing: "Editando", running: "Ejecutando", waiting: "Esperando", subagent: "Subagente",
        done: "Listo", stopped: "Detenido", failed: "Fallido", quiet: "Quieto", app: "App",
        terminal: "Terminal", remote: "Remoto", background: "Segundo plano", timeline: "Línea de tiempo",
        edits: "Cambios", thinkingTitle: "Pensando", reply: "Respuesta", showMore: "Mostrar más",
        sandbox: "Sandbox", truncated: "Recortado", denied: "Denegado", readWord: "Leer",
        searchWord: "Buscar", editWord: "Editar", runWord: "Ejecutar", deleteWord: "Borrar", mcpWord: "MCP",
        subagentWord: "Subagente", filesWord: "archivos", commandsWord: "comandos", failuresWord: "fallos",
        finishedWord: "Terminado", failedWord: "Fallido", needsYouWord: "Te necesita", inWord: "entrada",
        outWord: "salida", cacheReadWord: "caché leída", cacheWriteWord: "caché escrita"
    )
    static let sk = NotchCursorViewStrings(
        idle: "Nečinný", sent: "Odoslané", thinking: "Premýšľa", reading: "Číta", searching: "Hľadá",
        editing: "Upravuje", running: "Beží", waiting: "Čaká", subagent: "Subagent", done: "Hotovo",
        stopped: "Zastavené", failed: "Zlyhalo", quiet: "Ticho", app: "App", terminal: "Terminál",
        remote: "Vzdialené", background: "Na pozadí", timeline: "Priebeh", edits: "Úpravy",
        thinkingTitle: "Premýšľa", reply: "Odpoveď", showMore: "Zobraziť viac", sandbox: "Sandbox",
        truncated: "Skrátené", denied: "Zamietnuté", readWord: "Čítať", searchWord: "Hľadať",
        editWord: "Upraviť", runWord: "Spustiť", deleteWord: "Zmazať", mcpWord: "MCP",
        subagentWord: "Subagent", filesWord: "súbory", commandsWord: "príkazy", failuresWord: "zlyhania",
        finishedWord: "Hotovo", failedWord: "Zlyhalo", needsYouWord: "Potrebuje vás", inWord: "vstup",
        outWord: "výstup", cacheReadWord: "čítanie cache", cacheWriteWord: "zápis cache"
    )
    static let de = NotchCursorViewStrings(
        idle: "Bereit", sent: "Gesendet", thinking: "Denkt", reading: "Liest", searching: "Sucht",
        editing: "Bearbeitet", running: "Läuft", waiting: "Wartet", subagent: "Subagent", done: "Fertig",
        stopped: "Gestoppt", failed: "Fehlgeschlagen", quiet: "Ruhe", app: "App", terminal: "Terminal",
        remote: "Remote", background: "Hintergrund", timeline: "Verlauf", edits: "Änderungen",
        thinkingTitle: "Denkt", reply: "Antwort", showMore: "Mehr anzeigen", sandbox: "Sandbox",
        truncated: "Gekürzt", denied: "Abgelehnt", readWord: "Lesen", searchWord: "Suchen",
        editWord: "Bearbeiten", runWord: "Ausführen", deleteWord: "Löschen", mcpWord: "MCP",
        subagentWord: "Subagent", filesWord: "Dateien", commandsWord: "Befehle", failuresWord: "Fehler",
        finishedWord: "Fertig", failedWord: "Fehlgeschlagen", needsYouWord: "Braucht dich", inWord: "ein",
        outWord: "aus", cacheReadWord: "Cache gelesen", cacheWriteWord: "Cache geschrieben"
    )
    static let fr = NotchCursorViewStrings(
        idle: "Inactif", sent: "Envoyé", thinking: "Réflexion", reading: "Lecture", searching: "Recherche",
        editing: "Édition", running: "Exécution", waiting: "Attente", subagent: "Sous-agent",
        done: "Terminé", stopped: "Arrêté", failed: "Échec", quiet: "Calme", app: "App",
        terminal: "Terminal", remote: "Distant", background: "Arrière-plan", timeline: "Fil",
        edits: "Modifications", thinkingTitle: "Réflexion", reply: "Réponse", showMore: "Afficher plus",
        sandbox: "Sandbox", truncated: "Tronqué", denied: "Refusé", readWord: "Lire", searchWord: "Chercher",
        editWord: "Modifier", runWord: "Lancer", deleteWord: "Supprimer", mcpWord: "MCP",
        subagentWord: "Sous-agent", filesWord: "fichiers", commandsWord: "commandes", failuresWord: "échecs",
        finishedWord: "Terminé", failedWord: "Échec", needsYouWord: "A besoin de vous", inWord: "entrée",
        outWord: "sortie", cacheReadWord: "cache lu", cacheWriteWord: "cache écrit"
    )
    static let it = NotchCursorViewStrings(
        idle: "Inattivo", sent: "Inviato", thinking: "Pensiero", reading: "Lettura", searching: "Ricerca",
        editing: "Modifica", running: "Esecuzione", waiting: "Attesa", subagent: "Subagente", done: "Fatto",
        stopped: "Interrotto", failed: "Errore", quiet: "Quiete", app: "App", terminal: "Terminale",
        remote: "Remoto", background: "In background", timeline: "Cronologia", edits: "Modifiche",
        thinkingTitle: "Pensiero", reply: "Risposta", showMore: "Mostra altro", sandbox: "Sandbox",
        truncated: "Troncato", denied: "Negato", readWord: "Leggi", searchWord: "Cerca", editWord: "Modifica",
        runWord: "Esegui", deleteWord: "Elimina", mcpWord: "MCP", subagentWord: "Subagente",
        filesWord: "file", commandsWord: "comandi", failuresWord: "errori", finishedWord: "Finito",
        failedWord: "Errore", needsYouWord: "Ha bisogno di te", inWord: "in", outWord: "out",
        cacheReadWord: "cache letta", cacheWriteWord: "cache scritta"
    )
    static let ru = NotchCursorViewStrings(
        idle: "Свободен", sent: "Отправлено", thinking: "Думает", reading: "Читает", searching: "Ищет",
        editing: "Правит", running: "Выполняет", waiting: "Ждёт", subagent: "Субагент", done: "Готово",
        stopped: "Остановлен", failed: "Ошибка", quiet: "Тихо", app: "Приложение", terminal: "Терминал",
        remote: "Удалённо", background: "Фон", timeline: "Ход", edits: "Правки", thinkingTitle: "Думает",
        reply: "Ответ", showMore: "Показать ещё", sandbox: "Песочница", truncated: "Обрезано",
        denied: "Отклонено", readWord: "Читать", searchWord: "Искать", editWord: "Править",
        runWord: "Запустить", deleteWord: "Удалить", mcpWord: "MCP", subagentWord: "Субагент",
        filesWord: "файлы", commandsWord: "команды", failuresWord: "сбои", finishedWord: "Готово",
        failedWord: "Ошибка", needsYouWord: "Нужен ответ", inWord: "вход", outWord: "выход",
        cacheReadWord: "чтение кэша", cacheWriteWord: "запись кэша"
    )
    static let tr = NotchCursorViewStrings(
        idle: "Boşta", sent: "Gönderildi", thinking: "Düşünüyor", reading: "Okuyor", searching: "Arıyor",
        editing: "Düzenliyor", running: "Çalışıyor", waiting: "Bekliyor", subagent: "Alt ajan", done: "Bitti",
        stopped: "Durdu", failed: "Başarısız", quiet: "Sessiz", app: "Uygulama", terminal: "Terminal",
        remote: "Uzak", background: "Arka plan", timeline: "Akış", edits: "Düzenlemeler",
        thinkingTitle: "Düşünüyor", reply: "Yanıt", showMore: "Daha fazla", sandbox: "Sandbox",
        truncated: "Kısaltıldı", denied: "Reddedildi", readWord: "Oku", searchWord: "Ara", editWord: "Düzenle",
        runWord: "Çalıştır", deleteWord: "Sil", mcpWord: "MCP", subagentWord: "Alt ajan", filesWord: "dosya",
        commandsWord: "komut", failuresWord: "hata", finishedWord: "Bitti", failedWord: "Başarısız",
        needsYouWord: "Seni bekliyor", inWord: "giriş", outWord: "çıkış", cacheReadWord: "önbellek okuma",
        cacheWriteWord: "önbellek yazma"
    )
    static let ja = NotchCursorViewStrings(
        idle: "待機", sent: "送信", thinking: "思考", reading: "読込", searching: "検索", editing: "編集",
        running: "実行", waiting: "承認待ち", subagent: "サブエージェント", done: "完了", stopped: "停止",
        failed: "失敗", quiet: "休止", app: "アプリ", terminal: "ターミナル", remote: "リモート",
        background: "バックグラウンド", timeline: "経過", edits: "編集", thinkingTitle: "思考", reply: "返信",
        showMore: "もっと見る", sandbox: "サンドボックス", truncated: "省略", denied: "拒否", readWord: "読む",
        searchWord: "検索", editWord: "編集", runWord: "実行", deleteWord: "削除", mcpWord: "MCP",
        subagentWord: "サブエージェント", filesWord: "ファイル", commandsWord: "コマンド", failuresWord: "失敗",
        finishedWord: "完了", failedWord: "失敗", needsYouWord: "確認が必要", inWord: "入力", outWord: "出力",
        cacheReadWord: "キャッシュ読取", cacheWriteWord: "キャッシュ書込"
    )
    static let ko = NotchCursorViewStrings(
        idle: "대기", sent: "전송", thinking: "생각", reading: "읽기", searching: "검색", editing: "편집",
        running: "실행", waiting: "승인 대기", subagent: "하위 에이전트", done: "완료", stopped: "중지",
        failed: "실패", quiet: "조용", app: "앱", terminal: "터미널", remote: "원격", background: "백그라운드",
        timeline: "타임라인", edits: "편집", thinkingTitle: "생각", reply: "답변", showMore: "더 보기",
        sandbox: "샌드박스", truncated: "잘림", denied: "거부", readWord: "읽기", searchWord: "검색",
        editWord: "편집", runWord: "실행", deleteWord: "삭제", mcpWord: "MCP", subagentWord: "하위 에이전트",
        filesWord: "파일", commandsWord: "명령", failuresWord: "실패", finishedWord: "완료", failedWord: "실패",
        needsYouWord: "확인 필요", inWord: "입력", outWord: "출력", cacheReadWord: "캐시 읽기",
        cacheWriteWord: "캐시 쓰기"
    )
    static let uk = NotchCursorViewStrings(
        idle: "Вільний", sent: "Надіслано", thinking: "Думає", reading: "Читає", searching: "Шукає",
        editing: "Редагує", running: "Виконує", waiting: "Чекає", subagent: "Субагент", done: "Готово",
        stopped: "Зупинено", failed: "Помилка", quiet: "Тихо", app: "Застосунок", terminal: "Термінал",
        remote: "Віддалено", background: "Фон", timeline: "Хід", edits: "Зміни", thinkingTitle: "Думає",
        reply: "Відповідь", showMore: "Показати ще", sandbox: "Пісочниця", truncated: "Обрізано",
        denied: "Відхилено", readWord: "Читати", searchWord: "Шукати", editWord: "Змінити",
        runWord: "Запустити", deleteWord: "Видалити", mcpWord: "MCP", subagentWord: "Субагент",
        filesWord: "файли", commandsWord: "команди", failuresWord: "збої", finishedWord: "Готово",
        failedWord: "Помилка", needsYouWord: "Потрібна відповідь", inWord: "вхід", outWord: "вихід",
        cacheReadWord: "читання кешу", cacheWriteWord: "запис кешу"
    )
    static let zhHans = NotchCursorViewStrings(
        idle: "空闲", sent: "已发送", thinking: "思考", reading: "读取", searching: "搜索", editing: "编辑",
        running: "运行", waiting: "等待", subagent: "子代理", done: "完成", stopped: "已停止", failed: "失败",
        quiet: "安静", app: "应用", terminal: "终端", remote: "远程", background: "后台", timeline: "过程",
        edits: "编辑", thinkingTitle: "思考", reply: "回复", showMore: "显示更多", sandbox: "沙盒",
        truncated: "已截断", denied: "已拒绝", readWord: "读取", searchWord: "搜索", editWord: "编辑",
        runWord: "运行", deleteWord: "删除", mcpWord: "MCP", subagentWord: "子代理", filesWord: "个文件",
        commandsWord: "条命令", failuresWord: "次失败", finishedWord: "已完成", failedWord: "失败",
        needsYouWord: "需要你", inWord: "输入", outWord: "输出", cacheReadWord: "缓存读取", cacheWriteWord: "缓存写入"
    )
    static let zhTW = NotchCursorViewStrings(
        idle: "閒置", sent: "已傳送", thinking: "思考", reading: "讀取", searching: "搜尋", editing: "編輯",
        running: "執行", waiting: "等待", subagent: "子代理", done: "完成", stopped: "已停止", failed: "失敗",
        quiet: "安靜", app: "App", terminal: "終端機", remote: "遠端", background: "背景", timeline: "過程",
        edits: "編輯", thinkingTitle: "思考", reply: "回覆", showMore: "顯示更多", sandbox: "沙盒",
        truncated: "已截斷", denied: "已拒絕", readWord: "讀取", searchWord: "搜尋", editWord: "編輯",
        runWord: "執行", deleteWord: "刪除", mcpWord: "MCP", subagentWord: "子代理", filesWord: "個檔案",
        commandsWord: "個指令", failuresWord: "次失敗", finishedWord: "已完成", failedWord: "失敗",
        needsYouWord: "需要你", inWord: "輸入", outWord: "輸出", cacheReadWord: "快取讀取", cacheWriteWord: "快取寫入"
    )
    static let zhHK = NotchCursorViewStrings(
        idle: "閒置", sent: "已傳送", thinking: "思考", reading: "讀取", searching: "搜尋", editing: "編輯",
        running: "執行", waiting: "等待", subagent: "子代理", done: "完成", stopped: "已停止", failed: "失敗",
        quiet: "安靜", app: "App", terminal: "終端機", remote: "遠端", background: "背景", timeline: "過程",
        edits: "編輯", thinkingTitle: "思考", reply: "回覆", showMore: "顯示更多", sandbox: "沙盒",
        truncated: "已截斷", denied: "已拒絕", readWord: "讀取", searchWord: "搜尋", editWord: "編輯",
        runWord: "執行", deleteWord: "刪除", mcpWord: "MCP", subagentWord: "子代理", filesWord: "個檔案",
        commandsWord: "個指令", failuresWord: "次失敗", finishedWord: "已完成", failedWord: "失敗",
        needsYouWord: "需要你", inWord: "輸入", outWord: "輸出", cacheReadWord: "快取讀取", cacheWriteWord: "快取寫入"
    )
}
