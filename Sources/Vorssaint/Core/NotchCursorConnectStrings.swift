// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCursorConnectStrings {
    let statusNotInstalled: String
    let statusInstalled: String
    let statusNeedsUpdate: String
    let statusUnreadable: String
    let manualSteps: String
    let disconnectButton: String
    let repairButton: String
    let previewHeading: String
    let confirmButton: String
    let cancelButton: String
    let waitingTitle: String
    let waitingHint: String
    let connectedTitle: String
    let testConnection: String
    let testSucceeded: String
    let testFailed: String
    let lastEventPrefix: String
    let lastEventNone: String
    let otherCopyWarning: String
    let replaceCopiesButton: String
    let hooksUpdated: String
    let removeHooksTitle: String
    let removeHooksMessage: String
    let removeHooksConfirm: String
    let keepHooks: String
    let helperMissing: String
}

extension FeatureStrings {
    static func notchCursorConnect(_ language: AppLanguage) -> NotchCursorConnectStrings {
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

extension NotchCursorConnectStrings {
    static let enUS = NotchCursorConnectStrings(
        statusNotInstalled: "Not connected",
        statusInstalled: "Connected",
        statusNeedsUpdate: "Needs an update",
        statusUnreadable: "Can’t update the hooks file",
        manualSteps: "Make ~/.cursor/hooks.json a normal file with version 1, then try again.",
        disconnectButton: "Disconnect",
        repairButton: "Repair",
        previewHeading: "This change will be saved",
        confirmButton: "Confirm",
        cancelButton: "Cancel",
        waitingTitle: "Waiting for Cursor…",
        waitingHint: "Send any message in Cursor.",
        connectedTitle: "Cursor is connected",
        testConnection: "Test connection",
        testSucceeded: "The helper reached Vorssaint.",
        testFailed: "The helper could not reach Vorssaint.",
        lastEventPrefix: "Last event from Cursor",
        lastEventNone: "No event yet",
        otherCopyWarning: "Another Vorssaint copy is already in the hooks file. Replace it so two helpers do not answer the same approval.",
        replaceCopiesButton: "Replace other copies",
        hooksUpdated: "Cursor hooks were updated.",
        removeHooksTitle: "Remove Cursor hooks?",
        removeHooksMessage: "Cursor can keep working without them. The hooks file changes only if you remove them.",
        removeHooksConfirm: "Remove hooks",
        keepHooks: "Keep hooks",
        helperMissing: "The Cursor helper is not in this copy of Vorssaint."
    )

    static let ptBR = NotchCursorConnectStrings(
        statusNotInstalled: "Não conectado",
        statusInstalled: "Conectado",
        statusNeedsUpdate: "Precisa de atualização",
        statusUnreadable: "Não é possível atualizar o arquivo de hooks",
        manualSteps: "Deixe ~/.cursor/hooks.json como um arquivo normal com a versão 1 e tente de novo.",
        disconnectButton: "Desconectar",
        repairButton: "Reparar",
        previewHeading: "Esta alteração será salva",
        confirmButton: "Confirmar",
        cancelButton: "Cancelar",
        waitingTitle: "Aguardando o Cursor…",
        waitingHint: "Envie qualquer mensagem no Cursor.",
        connectedTitle: "O Cursor está conectado",
        testConnection: "Testar conexão",
        testSucceeded: "O assistente alcançou o Vorssaint.",
        testFailed: "O assistente não alcançou o Vorssaint.",
        lastEventPrefix: "Último evento do Cursor",
        lastEventNone: "Nenhum evento ainda",
        otherCopyWarning: "Outra cópia do Vorssaint já está no arquivo de hooks. Substitua-a para que dois assistentes não respondam à mesma aprovação.",
        replaceCopiesButton: "Substituir as outras cópias",
        hooksUpdated: "Os hooks do Cursor foram atualizados.",
        removeHooksTitle: "Remover os hooks do Cursor?",
        removeHooksMessage: "O Cursor continua funcionando sem eles. O arquivo de hooks só muda se você removê-los.",
        removeHooksConfirm: "Remover hooks",
        keepHooks: "Manter hooks",
        helperMissing: "O assistente do Cursor não está nesta cópia do Vorssaint."
    )

    static let es = NotchCursorConnectStrings(
        statusNotInstalled: "Sin conexión",
        statusInstalled: "Conectado",
        statusNeedsUpdate: "Necesita una actualización",
        statusUnreadable: "No se puede actualizar el archivo de hooks",
        manualSteps: "Deja ~/.cursor/hooks.json como un archivo normal con la versión 1 e inténtalo de nuevo.",
        disconnectButton: "Desconectar",
        repairButton: "Reparar",
        previewHeading: "Este cambio se guardará",
        confirmButton: "Confirmar",
        cancelButton: "Cancelar",
        waitingTitle: "Esperando a Cursor…",
        waitingHint: "Envía cualquier mensaje en Cursor.",
        connectedTitle: "Cursor está conectado",
        testConnection: "Probar conexión",
        testSucceeded: "El asistente llegó a Vorssaint.",
        testFailed: "El asistente no llegó a Vorssaint.",
        lastEventPrefix: "Último evento de Cursor",
        lastEventNone: "Aún no hay eventos",
        otherCopyWarning: "Otra copia de Vorssaint ya está en el archivo de hooks. Sustitúyela para que dos asistentes no respondan a la misma aprobación.",
        replaceCopiesButton: "Sustituir las otras copias",
        hooksUpdated: "Los hooks de Cursor se actualizaron.",
        removeHooksTitle: "¿Quitar los hooks de Cursor?",
        removeHooksMessage: "Cursor puede seguir funcionando sin ellos. El archivo de hooks solo cambia si los quitas.",
        removeHooksConfirm: "Quitar hooks",
        keepHooks: "Conservar hooks",
        helperMissing: "El asistente de Cursor no está en esta copia de Vorssaint."
    )

    static let sk = NotchCursorConnectStrings(
        statusNotInstalled: "Nepripojené",
        statusInstalled: "Pripojené",
        statusNeedsUpdate: "Vyžaduje aktualizáciu",
        statusUnreadable: "Súbor hooks sa nedá aktualizovať",
        manualSteps: "Nechaj ~/.cursor/hooks.json ako bežný súbor s verziou 1 a skús to znova.",
        disconnectButton: "Odpojiť",
        repairButton: "Opraviť",
        previewHeading: "Táto zmena sa uloží",
        confirmButton: "Potvrdiť",
        cancelButton: "Zrušiť",
        waitingTitle: "Čaká sa na Cursor…",
        waitingHint: "Pošli ľubovoľnú správu v Cursore.",
        connectedTitle: "Cursor je pripojený",
        testConnection: "Vyskúšať pripojenie",
        testSucceeded: "Pomocník dosiahol Vorssaint.",
        testFailed: "Pomocník nedosiahol Vorssaint.",
        lastEventPrefix: "Posledná udalosť z Cursoru",
        lastEventNone: "Zatiaľ žiadna udalosť",
        otherCopyWarning: "V súbore hooks už je iná kópia Vorssaint. Nahraď ju, aby dvaja pomocníci neodpovedali na to isté schválenie.",
        replaceCopiesButton: "Nahradiť ostatné kópie",
        hooksUpdated: "Hooks pre Cursor boli aktualizované.",
        removeHooksTitle: "Odstrániť hooks pre Cursor?",
        removeHooksMessage: "Cursor funguje aj bez nich. Súbor hooks sa zmení, len ak ich odstrániš.",
        removeHooksConfirm: "Odstrániť hooks",
        keepHooks: "Ponechať hooks",
        helperMissing: "Pomocník Cursor nie je v tejto kópii Vorssaint."
    )

    static let de = NotchCursorConnectStrings(
        statusNotInstalled: "Nicht verbunden",
        statusInstalled: "Verbunden",
        statusNeedsUpdate: "Aktualisierung nötig",
        statusUnreadable: "Die Hooks-Datei lässt sich nicht aktualisieren",
        manualSteps: "Mache ~/.cursor/hooks.json zu einer normalen Datei mit Version 1 und versuche es erneut.",
        disconnectButton: "Trennen",
        repairButton: "Reparieren",
        previewHeading: "Diese Änderung wird gespeichert",
        confirmButton: "Bestätigen",
        cancelButton: "Abbrechen",
        waitingTitle: "Warte auf Cursor…",
        waitingHint: "Sende eine beliebige Nachricht in Cursor.",
        connectedTitle: "Cursor ist verbunden",
        testConnection: "Verbindung prüfen",
        testSucceeded: "Der Helfer hat Vorssaint erreicht.",
        testFailed: "Der Helfer hat Vorssaint nicht erreicht.",
        lastEventPrefix: "Letztes Ereignis von Cursor",
        lastEventNone: "Noch kein Ereignis",
        otherCopyWarning: "Eine andere Vorssaint-Kopie steht bereits in der Hooks-Datei. Ersetze sie, damit nicht zwei Helfer dieselbe Freigabe beantworten.",
        replaceCopiesButton: "Andere Kopien ersetzen",
        hooksUpdated: "Die Cursor-Hooks wurden aktualisiert.",
        removeHooksTitle: "Cursor-Hooks entfernen?",
        removeHooksMessage: "Cursor funktioniert auch ohne sie. Die Hooks-Datei ändert sich nur, wenn du sie entfernst.",
        removeHooksConfirm: "Hooks entfernen",
        keepHooks: "Hooks behalten",
        helperMissing: "Der Cursor-Helfer ist in dieser Kopie von Vorssaint nicht enthalten."
    )

    static let fr = NotchCursorConnectStrings(
        statusNotInstalled: "Non connecté",
        statusInstalled: "Connecté",
        statusNeedsUpdate: "Mise à jour nécessaire",
        statusUnreadable: "Impossible de mettre à jour le fichier de hooks",
        manualSteps: "Fais de ~/.cursor/hooks.json un fichier ordinaire à la version 1, puis réessaie.",
        disconnectButton: "Déconnecter",
        repairButton: "Réparer",
        previewHeading: "Cette modification sera enregistrée",
        confirmButton: "Confirmer",
        cancelButton: "Annuler",
        waitingTitle: "En attente de Cursor…",
        waitingHint: "Envoie un message dans Cursor.",
        connectedTitle: "Cursor est connecté",
        testConnection: "Tester la connexion",
        testSucceeded: "L’assistant a joint Vorssaint.",
        testFailed: "L’assistant n’a pas joint Vorssaint.",
        lastEventPrefix: "Dernier événement de Cursor",
        lastEventNone: "Aucun événement pour l’instant",
        otherCopyWarning: "Une autre copie de Vorssaint est déjà dans le fichier de hooks. Remplace-la pour que deux assistants ne répondent pas à la même approbation.",
        replaceCopiesButton: "Remplacer les autres copies",
        hooksUpdated: "Les hooks Cursor ont été mis à jour.",
        removeHooksTitle: "Retirer les hooks Cursor\u{00A0}?",
        removeHooksMessage: "Cursor continue de fonctionner sans eux. Le fichier de hooks ne change que si tu les retires.",
        removeHooksConfirm: "Retirer les hooks",
        keepHooks: "Garder les hooks",
        helperMissing: "L’assistant Cursor n’est pas dans cette copie de Vorssaint."
    )

    static let it = NotchCursorConnectStrings(
        statusNotInstalled: "Non connesso",
        statusInstalled: "Connesso",
        statusNeedsUpdate: "Serve un aggiornamento",
        statusUnreadable: "Impossibile aggiornare il file degli hook",
        manualSteps: "Rendi ~/.cursor/hooks.json un file normale con versione 1, poi riprova.",
        disconnectButton: "Disconnetti",
        repairButton: "Ripara",
        previewHeading: "Questa modifica verrà salvata",
        confirmButton: "Conferma",
        cancelButton: "Annulla",
        waitingTitle: "In attesa di Cursor…",
        waitingHint: "Invia un messaggio qualsiasi in Cursor.",
        connectedTitle: "Cursor è connesso",
        testConnection: "Prova la connessione",
        testSucceeded: "L’assistente ha raggiunto Vorssaint.",
        testFailed: "L’assistente non ha raggiunto Vorssaint.",
        lastEventPrefix: "Ultimo evento da Cursor",
        lastEventNone: "Nessun evento",
        otherCopyWarning: "Un’altra copia di Vorssaint è già nel file degli hook. Sostituiscila così due assistenti non rispondono alla stessa approvazione.",
        replaceCopiesButton: "Sostituisci le altre copie",
        hooksUpdated: "Gli hook di Cursor sono stati aggiornati.",
        removeHooksTitle: "Rimuovere gli hook di Cursor?",
        removeHooksMessage: "Cursor continua a funzionare senza. Il file degli hook cambia solo se li rimuovi.",
        removeHooksConfirm: "Rimuovi gli hook",
        keepHooks: "Tieni gli hook",
        helperMissing: "L’assistente di Cursor non è in questa copia di Vorssaint."
    )

    static let ru = NotchCursorConnectStrings(
        statusNotInstalled: "Не подключено",
        statusInstalled: "Подключено",
        statusNeedsUpdate: "Нужно обновление",
        statusUnreadable: "Не удаётся обновить файл hooks",
        manualSteps: "Сделайте ~/.cursor/hooks.json обычным файлом с версией 1 и повторите попытку.",
        disconnectButton: "Отключить",
        repairButton: "Исправить",
        previewHeading: "Это изменение будет сохранено",
        confirmButton: "Подтвердить",
        cancelButton: "Отмена",
        waitingTitle: "Ожидание Cursor…",
        waitingHint: "Отправьте любое сообщение в Cursor.",
        connectedTitle: "Cursor подключён",
        testConnection: "Проверить соединение",
        testSucceeded: "Помощник достучался до Vorssaint.",
        testFailed: "Помощник не достучался до Vorssaint.",
        lastEventPrefix: "Последнее событие от Cursor",
        lastEventNone: "Событий пока нет",
        otherCopyWarning: "В файле hooks уже есть другая копия Vorssaint. Замените её, чтобы два помощника не отвечали на одно подтверждение.",
        replaceCopiesButton: "Заменить другие копии",
        hooksUpdated: "Хуки Cursor обновлены.",
        removeHooksTitle: "Удалить хуки Cursor?",
        removeHooksMessage: "Cursor работает и без них. Файл hooks изменится, только если вы их удалите.",
        removeHooksConfirm: "Удалить хуки",
        keepHooks: "Оставить хуки",
        helperMissing: "Помощник Cursor отсутствует в этой копии Vorssaint."
    )

    static let tr = NotchCursorConnectStrings(
        statusNotInstalled: "Bağlı değil",
        statusInstalled: "Bağlandı",
        statusNeedsUpdate: "Güncelleme gerekli",
        statusUnreadable: "Kanca dosyası güncellenemiyor",
        manualSteps: "~/.cursor/hooks.json dosyasını sürüm 1 olan normal bir dosya yapın ve yeniden deneyin.",
        disconnectButton: "Bağlantıyı kes",
        repairButton: "Onar",
        previewHeading: "Bu değişiklik kaydedilecek",
        confirmButton: "Onayla",
        cancelButton: "Vazgeç",
        waitingTitle: "Cursor bekleniyor…",
        waitingHint: "Cursor’da herhangi bir ileti gönderin.",
        connectedTitle: "Cursor bağlı",
        testConnection: "Bağlantıyı dene",
        testSucceeded: "Yardımcı Vorssaint’e ulaştı.",
        testFailed: "Yardımcı Vorssaint’e ulaşamadı.",
        lastEventPrefix: "Cursor’dan son olay",
        lastEventNone: "Henüz olay yok",
        otherCopyWarning: "Kanca dosyasında başka bir Vorssaint kopyası var. Aynı onayı iki yardımcının yanıtlamaması için onu değiştirin.",
        replaceCopiesButton: "Diğer kopyaları değiştir",
        hooksUpdated: "Cursor kancaları güncellendi.",
        removeHooksTitle: "Cursor kancaları kaldırılsın mı?",
        removeHooksMessage: "Cursor onlarsız da çalışır. Kanca dosyası yalnızca kaldırırsanız değişir.",
        removeHooksConfirm: "Kancaları kaldır",
        keepHooks: "Kancaları tut",
        helperMissing: "Cursor yardımcısı bu Vorssaint kopyasında yok."
    )

    static let ja = NotchCursorConnectStrings(
        statusNotInstalled: "未接続",
        statusInstalled: "接続済み",
        statusNeedsUpdate: "更新が必要です",
        statusUnreadable: "フックスファイルを更新できません",
        manualSteps: "~/.cursor/hooks.json をバージョン 1 の通常のファイルにしてから、もう一度試してください。",
        disconnectButton: "切断",
        repairButton: "修復",
        previewHeading: "この変更が保存されます",
        confirmButton: "確認",
        cancelButton: "キャンセル",
        waitingTitle: "Cursor を待っています…",
        waitingHint: "Cursor でメッセージを送ってください。",
        connectedTitle: "Cursor は接続されています",
        testConnection: "接続を試す",
        testSucceeded: "ヘルパーが Vorssaint に届きました。",
        testFailed: "ヘルパーが Vorssaint に届きませんでした。",
        lastEventPrefix: "Cursor からの最後のイベント",
        lastEventNone: "まだイベントはありません",
        otherCopyWarning: "別の Vorssaint がフックスファイルに入っています。同じ承認に二つのヘルパーが答えないよう、置き換えてください。",
        replaceCopiesButton: "ほかのコピーを置き換える",
        hooksUpdated: "Cursor のフックスを更新しました。",
        removeHooksTitle: "Cursor のフックスを外しますか？",
        removeHooksMessage: "Cursor はフックスがなくても動きます。外したときだけファイルが変わります。",
        removeHooksConfirm: "フックスを外す",
        keepHooks: "フックスを残す",
        helperMissing: "この Vorssaint には Cursor ヘルパーがありません。"
    )

    static let ko = NotchCursorConnectStrings(
        statusNotInstalled: "연결되지 않음",
        statusInstalled: "연결됨",
        statusNeedsUpdate: "업데이트가 필요합니다",
        statusUnreadable: "훅 파일을 업데이트할 수 없습니다",
        manualSteps: "~/.cursor/hooks.json을 버전 1인 일반 파일로 만든 다음 다시 시도하세요.",
        disconnectButton: "연결 해제",
        repairButton: "복구",
        previewHeading: "이 변경이 저장됩니다",
        confirmButton: "확인",
        cancelButton: "취소",
        waitingTitle: "Cursor를 기다리는 중…",
        waitingHint: "Cursor에서 아무 메시지나 보내세요.",
        connectedTitle: "Cursor가 연결되었습니다",
        testConnection: "연결 시험",
        testSucceeded: "도우미가 Vorssaint에 도달했습니다.",
        testFailed: "도우미가 Vorssaint에 도달하지 못했습니다.",
        lastEventPrefix: "Cursor의 마지막 이벤트",
        lastEventNone: "아직 이벤트 없음",
        otherCopyWarning: "다른 Vorssaint 사본이 훅 파일에 있습니다. 두 도우미가 같은 승인에 답하지 않도록 바꾸세요.",
        replaceCopiesButton: "다른 사본 바꾸기",
        hooksUpdated: "Cursor 훅을 업데이트했습니다.",
        removeHooksTitle: "Cursor 훅을 제거할까요?",
        removeHooksMessage: "Cursor는 훅 없이도 동작합니다. 훅 파일은 제거할 때만 바뀝니다.",
        removeHooksConfirm: "훅 제거",
        keepHooks: "훅 유지",
        helperMissing: "이 Vorssaint 사본에는 Cursor 도우미가 없습니다."
    )

    static let uk = NotchCursorConnectStrings(
        statusNotInstalled: "Не підключено",
        statusInstalled: "Підключено",
        statusNeedsUpdate: "Потрібне оновлення",
        statusUnreadable: "Не вдається оновити файл hooks",
        manualSteps: "Зробіть ~/.cursor/hooks.json звичайним файлом із версією 1 і спробуйте знову.",
        disconnectButton: "Відключити",
        repairButton: "Відновити",
        previewHeading: "Цю зміну буде збережено",
        confirmButton: "Підтвердити",
        cancelButton: "Скасувати",
        waitingTitle: "Очікування Cursor…",
        waitingHint: "Надішліть будь-яке повідомлення в Cursor.",
        connectedTitle: "Cursor підключено",
        testConnection: "Перевірити з’єднання",
        testSucceeded: "Помічник досяг Vorssaint.",
        testFailed: "Помічник не досяг Vorssaint.",
        lastEventPrefix: "Остання подія від Cursor",
        lastEventNone: "Подій ще немає",
        otherCopyWarning: "У файлі hooks уже є інша копія Vorssaint. Замініть її, щоб два помічники не відповідали на одне схвалення.",
        replaceCopiesButton: "Замінити інші копії",
        hooksUpdated: "Хуки Cursor оновлено.",
        removeHooksTitle: "Видалити хуки Cursor?",
        removeHooksMessage: "Cursor працює і без них. Файл hooks зміниться, лише якщо ви їх видалите.",
        removeHooksConfirm: "Видалити хуки",
        keepHooks: "Залишити хуки",
        helperMissing: "Помічника Cursor немає в цій копії Vorssaint."
    )

    static let zhHans = NotchCursorConnectStrings(
        statusNotInstalled: "未连接",
        statusInstalled: "已连接",
        statusNeedsUpdate: "需要更新",
        statusUnreadable: "无法更新钩子文件",
        manualSteps: "请将 ~/.cursor/hooks.json 设为版本为 1 的普通文件，然后再试一次。",
        disconnectButton: "断开",
        repairButton: "修复",
        previewHeading: "此更改将被保存",
        confirmButton: "确认",
        cancelButton: "取消",
        waitingTitle: "正在等待 Cursor…",
        waitingHint: "在 Cursor 中发送任意消息。",
        connectedTitle: "Cursor 已连接",
        testConnection: "测试连接",
        testSucceeded: "辅助程序已连上 Vorssaint。",
        testFailed: "辅助程序未能连上 Vorssaint。",
        lastEventPrefix: "来自 Cursor 的上次事件",
        lastEventNone: "还没有事件",
        otherCopyWarning: "钩子文件里已有另一份 Vorssaint。请替换它，以免两个辅助程序回应同一次批准。",
        replaceCopiesButton: "替换其他副本",
        hooksUpdated: "已更新 Cursor 钩子。",
        removeHooksTitle: "要移除 Cursor 钩子吗？",
        removeHooksMessage: "没有这些钩子，Cursor 仍可使用。只有在你移除时，钩子文件才会改变。",
        removeHooksConfirm: "移除钩子",
        keepHooks: "保留钩子",
        helperMissing: "此 Vorssaint 副本中没有 Cursor 辅助程序。"
    )

    static let zhTW = NotchCursorConnectStrings(
        statusNotInstalled: "未連線",
        statusInstalled: "已連線",
        statusNeedsUpdate: "需要更新",
        statusUnreadable: "無法更新鉤子檔案",
        manualSteps: "請將 ~/.cursor/hooks.json 設為版本 1 的一般檔案，然後再試一次。",
        disconnectButton: "中斷連線",
        repairButton: "修復",
        previewHeading: "這項變更將會儲存",
        confirmButton: "確認",
        cancelButton: "取消",
        waitingTitle: "正在等候 Cursor…",
        waitingHint: "在 Cursor 中傳送任一則訊息。",
        connectedTitle: "Cursor 已連線",
        testConnection: "測試連線",
        testSucceeded: "輔助程式已連上 Vorssaint。",
        testFailed: "輔助程式未能連上 Vorssaint。",
        lastEventPrefix: "來自 Cursor 的上次事件",
        lastEventNone: "尚未有事件",
        otherCopyWarning: "鉤子檔案中已有另一份 Vorssaint。請替換它，以免兩個輔助程式回應同一次核准。",
        replaceCopiesButton: "替換其他複本",
        hooksUpdated: "已更新 Cursor 鉤子。",
        removeHooksTitle: "要移除 Cursor 鉤子嗎？",
        removeHooksMessage: "沒有這些鉤子，Cursor 仍可使用。只有在你移除時，鉤子檔案才會改變。",
        removeHooksConfirm: "移除鉤子",
        keepHooks: "保留鉤子",
        helperMissing: "此 Vorssaint 複本中沒有 Cursor 輔助程式。"
    )

    static let zhHK = NotchCursorConnectStrings(
        statusNotInstalled: "未連接",
        statusInstalled: "已連接",
        statusNeedsUpdate: "需要更新",
        statusUnreadable: "無法更新鉤子檔案",
        manualSteps: "請將 ~/.cursor/hooks.json 設為版本 1 的普通檔案，然後再試一次。",
        disconnectButton: "中斷連接",
        repairButton: "修復",
        previewHeading: "這項變更將會儲存",
        confirmButton: "確認",
        cancelButton: "取消",
        waitingTitle: "正在等候 Cursor…",
        waitingHint: "在 Cursor 中傳送任何訊息。",
        connectedTitle: "Cursor 已連接",
        testConnection: "測試連接",
        testSucceeded: "輔助程式已連上 Vorssaint。",
        testFailed: "輔助程式未能連上 Vorssaint。",
        lastEventPrefix: "來自 Cursor 的上次事件",
        lastEventNone: "尚未有事件",
        otherCopyWarning: "鉤子檔案中已有另一份 Vorssaint。請替換它，以免兩個輔助程式回應同一次核准。",
        replaceCopiesButton: "替換其他複本",
        hooksUpdated: "已更新 Cursor 鉤子。",
        removeHooksTitle: "要移除 Cursor 鉤子嗎？",
        removeHooksMessage: "沒有這些鉤子，Cursor 仍可使用。只有在你移除時，鉤子檔案才會改變。",
        removeHooksConfirm: "移除鉤子",
        keepHooks: "保留鉤子",
        helperMissing: "此 Vorssaint 複本中沒有 Cursor 輔助程式。"
    )
}
