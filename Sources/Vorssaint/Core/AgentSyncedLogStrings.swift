// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The folders of agent logs synced from other computers, on the AI page.
struct AgentSyncedLogStrings {
    let title: String
    let explanation: String
    let add: String
    let remove: String
    /// Under a folder that is not there now.
    let missing: String
}

extension FeatureStrings {
    static func agentSyncedLogs(_ language: AppLanguage) -> AgentSyncedLogStrings {
        switch language {
        case .enUS: return AgentSyncedLogStrings(
            title: "Other computers",
            explanation: "Add a folder where another tool, such as Syncthing, copies Claude Code or Codex logs from another computer. Their usage counts with this Mac’s in Spending, Projects and Activity, but their sessions never show as running here. The folder is only read: nothing is synced or sent from here.",
            add: "Add folder…",
            remove: "Remove this folder",
            missing: "Folder not found")
        case .ptBR: return AgentSyncedLogStrings(
            title: "Outros computadores",
            explanation: "Adicione uma pasta para a qual outra ferramenta, como o Syncthing, copia os registros do Claude Code ou do Codex de outro computador. O uso deles conta junto com o deste Mac em Gastos, Projetos e Atividade, mas as sessões deles nunca aparecem em andamento aqui. A pasta é só lida: nada é sincronizado ou enviado daqui.",
            add: "Adicionar pasta…",
            remove: "Remover esta pasta",
            missing: "Pasta não encontrada")
        case .tr: return AgentSyncedLogStrings(
            title: "Diğer bilgisayarlar",
            explanation: "Syncthing gibi başka bir aracın, başka bir bilgisayardaki Claude Code veya Codex kayıtlarını kopyaladığı bir klasör ekleyin. Bu kayıtlardaki kullanım Harcama, Projeler ve Etkinlik’te bu Mac’inkiyle birlikte sayılır, ancak oradaki oturumlar burada hiçbir zaman çalışıyor olarak görünmez. Klasör yalnızca okunur: buradan hiçbir şey eşitlenmez veya gönderilmez.",
            add: "Klasör ekle…",
            remove: "Bu klasörü kaldır",
            missing: "Klasör bulunamadı")
        case .ru: return AgentSyncedLogStrings(
            title: "Другие компьютеры",
            explanation: "Добавьте папку, в которую другая программа, например Syncthing, копирует журналы Claude Code или Codex с другого компьютера. Их использование учитывается вместе с этим Mac в разделах «Расходы», «Проекты» и «Активность», но их сеансы никогда не показываются здесь как идущие. Папка только читается: отсюда ничего не синхронизируется и не отправляется.",
            add: "Добавить папку…",
            remove: "Удалить эту папку",
            missing: "Папка не найдена")
        case .es: return AgentSyncedLogStrings(
            title: "Otros ordenadores",
            explanation: "Añade una carpeta en la que otra herramienta, como Syncthing, copia los registros de Claude Code o Codex de otro ordenador. Su uso cuenta junto con el de este Mac en Gasto, Proyectos y Actividad, pero sus sesiones nunca aparecen en curso aquí. La carpeta solo se lee: desde aquí no se sincroniza ni se envía nada.",
            add: "Añadir carpeta…",
            remove: "Quitar esta carpeta",
            missing: "No se encontró la carpeta")
        case .sk: return AgentSyncedLogStrings(
            title: "Iné počítače",
            explanation: "Pridajte priečinok, do ktorého iný nástroj, napríklad Syncthing, kopíruje záznamy Claude Code alebo Codex z iného počítača. Ich využitie sa započíta spolu s týmto Macom do Výdavkov, Projektov a Aktivity, ich relácie sa tu však nikdy nezobrazia ako spustené. Priečinok sa iba číta: odtiaľto sa nič nesynchronizuje ani neodosiela.",
            add: "Pridať priečinok…",
            remove: "Odstrániť tento priečinok",
            missing: "Priečinok sa nenašiel")
        case .de: return AgentSyncedLogStrings(
            title: "Andere Computer",
            explanation: "Füge einen Ordner hinzu, in den ein anderes Tool wie Syncthing die Claude-Code- oder Codex-Protokolle eines anderen Computers kopiert. Deren Nutzung zählt in „Ausgaben“, „Projekte“ und „Aktivität“ zu der dieses Macs, ihre Sitzungen erscheinen hier aber nie als laufend. Der Ordner wird nur gelesen: Von hier wird nichts synchronisiert oder gesendet.",
            add: "Ordner hinzufügen…",
            remove: "Diesen Ordner entfernen",
            missing: "Ordner nicht gefunden")
        case .fr: return AgentSyncedLogStrings(
            title: "Autres ordinateurs",
            explanation: "Ajoutez un dossier dans lequel un autre outil, comme Syncthing, copie les journaux Claude Code ou Codex d’un autre ordinateur. Leur usage compte avec celui de ce Mac dans Dépenses, Projets et Activité, mais leurs sessions n’apparaissent jamais en cours ici. Le dossier est seulement lu : rien n’est synchronisé ni envoyé d’ici.",
            add: "Ajouter un dossier…",
            remove: "Retirer ce dossier",
            missing: "Dossier introuvable")
        case .it: return AgentSyncedLogStrings(
            title: "Altri computer",
            explanation: "Aggiungi una cartella in cui un altro strumento, come Syncthing, copia i log di Claude Code o Codex di un altro computer. Il loro utilizzo si somma a quello di questo Mac in Spesa, Progetti e Attività, ma le loro sessioni non appaiono mai in corso qui. La cartella viene solo letta: da qui non si sincronizza né si invia nulla.",
            add: "Aggiungi cartella…",
            remove: "Rimuovi questa cartella",
            missing: "Cartella non trovata")
        case .ja: return AgentSyncedLogStrings(
            title: "ほかのコンピュータ",
            explanation: "Syncthingなどのツールが、ほかのコンピュータのClaude CodeやCodexのログをコピーするフォルダを追加します。その使用量は使用額、プロジェクト、アクティビティでこのMacの分と合わせて数えられますが、そちらのセッションがここで実行中として表示されることはありません。フォルダは読み取るだけで、ここから同期や送信は行いません。",
            add: "フォルダを追加…",
            remove: "このフォルダを削除",
            missing: "フォルダが見つかりません")
        case .ko: return AgentSyncedLogStrings(
            title: "다른 컴퓨터",
            explanation: "Syncthing 같은 다른 도구가 다른 컴퓨터의 Claude Code 또는 Codex 로그를 복사해 두는 폴더를 추가하세요. 그 사용량은 사용 금액, 프로젝트, 활동에서 이 Mac의 사용량과 함께 집계되지만, 그곳의 세션은 여기에서 실행 중으로 표시되지 않습니다. 폴더는 읽기만 하며, 여기에서 아무것도 동기화하거나 보내지 않습니다.",
            add: "폴더 추가…",
            remove: "이 폴더 제거",
            missing: "폴더를 찾을 수 없음")
        case .uk: return AgentSyncedLogStrings(
            title: "Інші комп’ютери",
            explanation: "Додайте папку, у яку інша програма, наприклад Syncthing, копіює журнали Claude Code або Codex з іншого комп’ютера. Їхнє використання враховується разом із цим Mac у розділах «Витрати», «Проєкти» та «Активність», але їхні сеанси ніколи не показуються тут як активні. Папка лише читається: звідси нічого не синхронізується й не надсилається.",
            add: "Додати папку…",
            remove: "Вилучити цю папку",
            missing: "Папку не знайдено")
        case .zhHans: return AgentSyncedLogStrings(
            title: "其他电脑",
            explanation: "添加一个文件夹，由 Syncthing 等其他工具把另一台电脑上的 Claude Code 或 Codex 日志复制到这里。其中的用量会在花费、项目和活动中与这台 Mac 的用量一起计算，但那里的会话不会在这里显示为正在运行。此文件夹只会被读取：不会从这里同步或发送任何内容。",
            add: "添加文件夹…",
            remove: "移除此文件夹",
            missing: "找不到文件夹")
        case .zhTW: return AgentSyncedLogStrings(
            title: "其他電腦",
            explanation: "加入一個資料夾，由 Syncthing 等其他工具把另一台電腦上的 Claude Code 或 Codex 記錄複製到這裡。其中的用量會在花費、專案和活動中與這台 Mac 的用量一起計算，但那裡的工作階段不會在這裡顯示為執行中。此資料夾只會被讀取：不會從這裡同步或傳送任何內容。",
            add: "加入資料夾…",
            remove: "移除此資料夾",
            missing: "找不到資料夾")
        case .zhHK: return AgentSyncedLogStrings(
            title: "其他電腦",
            explanation: "加入一個資料夾，由 Syncthing 等其他工具把另一部電腦上的 Claude Code 或 Codex 記錄複製到這裡。當中的用量會在花費、項目和活動中與這部 Mac 的用量一併計算，但那邊的工作階段不會在這裡顯示為執行中。此資料夾只會被讀取：不會從這裡同步或傳送任何內容。",
            add: "加入資料夾…",
            remove: "移除此資料夾",
            missing: "找不到資料夾")
        }
    }
}
