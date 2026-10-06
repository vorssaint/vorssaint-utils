// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct T3CodeStrings {
    let source: String
    let working: String
    let waiting: String
    let waitingInput: String
    let approval: String
    let completed: String
    let failed: String
    let stopped: String
    let idle: String
    let endpoint: String
    let pairingCode: String
    let connect: String
    let disconnect: String
    let pairHelp: String
    let remoteHelp: String
    let notConnected: String
    let connecting: String
    let connected: String
    let reconnecting: String
    let needsPairing: String
    let unavailable: String
    let workingCount: (Int) -> String
    let errors: (T3CodeConnectionError) -> String

    init(_ language: AppLanguage) {
        switch language {
        case .enUS:
            source = "T3 Code"; working = "working"; waiting = "waiting"; waitingInput = "waiting for input"
            approval = "approval needed"; completed = "completed"; failed = "failed"; stopped = "stopped"; idle = "idle"
            endpoint = "T3 endpoint"; pairingCode = "One-time pairing code"; connect = "Connect"; disconnect = "Disconnect"
            pairHelp = "Create a short-lived, read-only code in T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Use the local endpoint or a trusted remote HTTPS endpoint. Vorssaint reads thread status only."
            notConnected = "Not connected"; connecting = "Connecting"; connected = "Connected"; reconnecting = "Reconnecting"
            needsPairing = "Pair again to restore read access"; unavailable = "T3 endpoint unavailable"
            workingCount = { "\($0) working" }; errors = Self.englishError
        case .ptBR:
            source = "T3 Code"; working = "em execução"; waiting = "aguardando"; waitingInput = "aguardando entrada"
            approval = "aprovação necessária"; completed = "concluído"; failed = "falhou"; stopped = "parado"; idle = "ocioso"
            endpoint = "Endpoint do T3"; pairingCode = "Código de pareamento temporário"; connect = "Conectar"; disconnect = "Desconectar"
            pairHelp = "Crie um código temporário somente de leitura no T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Use o endpoint local ou um endpoint HTTPS remoto confiável. O Vorssaint lê apenas o estado das conversas."
            notConnected = "Não conectado"; connecting = "Conectando"; connected = "Conectado"; reconnecting = "Reconectando"
            needsPairing = "Pareie novamente para restaurar o acesso"; unavailable = "Endpoint do T3 indisponível"
            workingCount = { "\($0) em execução" }; errors = Self.portugueseError
        case .tr:
            source = "T3 Code"; working = "çalışıyor"; waiting = "bekliyor"; waitingInput = "girdi bekliyor"
            approval = "onay gerekiyor"; completed = "tamamlandı"; failed = "başarısız"; stopped = "durduruldu"; idle = "boşta"
            endpoint = "T3 uç noktası"; pairingCode = "Tek kullanımlık eşleştirme kodu"; connect = "Bağlan"; disconnect = "Bağlantıyı kes"
            pairHelp = "T3 Code’da kısa süreli, salt okunur kod oluşturun: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Yerel veya güvenilir bir uzak HTTPS uç noktası kullanın. Vorssaint yalnızca iş parçacığı durumunu okur."
            notConnected = "Bağlı değil"; connecting = "Bağlanıyor"; connected = "Bağlı"; reconnecting = "Yeniden bağlanıyor"
            needsPairing = "Okuma erişimi için yeniden eşleştirin"; unavailable = "T3 uç noktasına ulaşılamıyor"
            workingCount = { "\($0) çalışıyor" }; errors = { Self.localizedError($0, language: language) }
        case .ru:
            source = "T3 Code"; working = "работает"; waiting = "ожидание"; waitingInput = "ожидает ввода"
            approval = "нужно подтверждение"; completed = "завершено"; failed = "ошибка"; stopped = "остановлено"; idle = "без работы"
            endpoint = "Адрес T3"; pairingCode = "Одноразовый код сопряжения"; connect = "Подключить"; disconnect = "Отключить"
            pairHelp = "Создайте временный код только для чтения в T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Укажите локальный или доверенный удалённый HTTPS-адрес. Vorssaint читает только состояние задач."
            notConnected = "Нет подключения"; connecting = "Подключение"; connected = "Подключено"; reconnecting = "Повторное подключение"
            needsPairing = "Повторите сопряжение для доступа на чтение"; unavailable = "Адрес T3 недоступен"
            workingCount = { "\($0) работает" }; errors = { Self.localizedError($0, language: language) }
        case .es:
            source = "T3 Code"; working = "en curso"; waiting = "en espera"; waitingInput = "esperando entrada"
            approval = "requiere aprobación"; completed = "completado"; failed = "fallido"; stopped = "detenido"; idle = "inactivo"
            endpoint = "Dirección de T3"; pairingCode = "Código de emparejamiento de un solo uso"; connect = "Conectar"; disconnect = "Desconectar"
            pairHelp = "Crea un código temporal de solo lectura en T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Usa la dirección local o una dirección HTTPS remota de confianza. Vorssaint solo lee el estado de los hilos."
            notConnected = "Sin conexión"; connecting = "Conectando"; connected = "Conectado"; reconnecting = "Reconectando"
            needsPairing = "Vuelve a emparejar para recuperar el acceso"; unavailable = "Dirección de T3 no disponible"
            workingCount = { "\($0) en curso" }; errors = { Self.localizedError($0, language: language) }
        case .sk:
            source = "T3 Code"; working = "pracuje"; waiting = "čaká"; waitingInput = "čaká na vstup"
            approval = "vyžaduje schválenie"; completed = "dokončené"; failed = "zlyhalo"; stopped = "zastavené"; idle = "nečinné"
            endpoint = "T3 adresa"; pairingCode = "Jednorazový párovací kód"; connect = "Pripojiť"; disconnect = "Odpojiť"
            pairHelp = "Vytvorte krátkodobý kód iba na čítanie v T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Použite lokálnu alebo dôveryhodnú vzdialenú HTTPS adresu. Vorssaint číta iba stav vlákien."
            notConnected = "Nepripojené"; connecting = "Pripája sa"; connected = "Pripojené"; reconnecting = "Znova sa pripája"
            needsPairing = "Na obnovenie prístupu sa znova spárujte"; unavailable = "T3 adresa nie je dostupná"
            workingCount = { "\($0) pracuje" }; errors = { Self.localizedError($0, language: language) }
        case .de:
            source = "T3 Code"; working = "arbeitet"; waiting = "wartet"; waitingInput = "wartet auf Eingabe"
            approval = "Freigabe nötig"; completed = "abgeschlossen"; failed = "fehlgeschlagen"; stopped = "gestoppt"; idle = "inaktiv"
            endpoint = "T3-Endpunkt"; pairingCode = "Einmaliger Kopplungscode"; connect = "Verbinden"; disconnect = "Trennen"
            pairHelp = "Erstelle in T3 Code einen kurzlebigen Nur-Lese-Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Verwende den lokalen oder einen vertrauenswürdigen HTTPS-Endpunkt. Vorssaint liest nur Thread-Status."
            notConnected = "Nicht verbunden"; connecting = "Verbindung wird hergestellt"; connected = "Verbunden"; reconnecting = "Verbindung wird wiederhergestellt"
            needsPairing = "Für den Lesezugriff erneut koppeln"; unavailable = "T3-Endpunkt nicht erreichbar"
            workingCount = { "\($0) arbeiten" }; errors = { Self.localizedError($0, language: language) }
        case .fr:
            source = "T3 Code"; working = "en cours"; waiting = "en attente"; waitingInput = "en attente d’une réponse"
            approval = "approbation requise"; completed = "terminé"; failed = "échec"; stopped = "arrêté"; idle = "inactif"
            endpoint = "Adresse T3"; pairingCode = "Code d’association à usage unique"; connect = "Connecter"; disconnect = "Déconnecter"
            pairHelp = "Créez un code temporaire en lecture seule dans T3 Code : t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Utilisez l’adresse locale ou une adresse HTTPS distante de confiance. Vorssaint lit uniquement l’état des fils."
            notConnected = "Non connecté"; connecting = "Connexion"; connected = "Connecté"; reconnecting = "Reconnexion"
            needsPairing = "Associez de nouveau pour rétablir l’accès"; unavailable = "Adresse T3 indisponible"
            workingCount = { "\($0) en cours" }; errors = { Self.localizedError($0, language: language) }
        case .it:
            source = "T3 Code"; working = "in esecuzione"; waiting = "in attesa"; waitingInput = "in attesa di input"
            approval = "approvazione necessaria"; completed = "completato"; failed = "non riuscito"; stopped = "fermato"; idle = "inattivo"
            endpoint = "Endpoint T3"; pairingCode = "Codice di associazione monouso"; connect = "Connetti"; disconnect = "Disconnetti"
            pairHelp = "Crea un codice temporaneo di sola lettura in T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Usa l’endpoint locale o un endpoint HTTPS remoto affidabile. Vorssaint legge solo lo stato dei thread."
            notConnected = "Non connesso"; connecting = "Connessione"; connected = "Connesso"; reconnecting = "Riconnessione"
            needsPairing = "Associa di nuovo per ripristinare l’accesso"; unavailable = "Endpoint T3 non disponibile"
            workingCount = { "\($0) in esecuzione" }; errors = { Self.localizedError($0, language: language) }
        case .ja:
            source = "T3 Code"; working = "作業中"; waiting = "待機中"; waitingInput = "入力待ち"
            approval = "承認が必要"; completed = "完了"; failed = "失敗"; stopped = "停止"; idle = "アイドル"
            endpoint = "T3 エンドポイント"; pairingCode = "1 回限りのペアリングコード"; connect = "接続"; disconnect = "切断"
            pairHelp = "T3 Code で短時間の読み取り専用コードを作成: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "ローカルまたは信頼できるリモート HTTPS を指定してください。Vorssaint はスレッド状態のみ読み取ります。"
            notConnected = "未接続"; connecting = "接続中"; connected = "接続済み"; reconnecting = "再接続中"
            needsPairing = "読み取りアクセスを復元するには再ペアリングしてください"; unavailable = "T3 エンドポイントに接続できません"
            workingCount = { "\($0) 件作業中" }; errors = { Self.localizedError($0, language: language) }
        case .ko:
            source = "T3 Code"; working = "작업 중"; waiting = "대기 중"; waitingInput = "입력 대기 중"
            approval = "승인 필요"; completed = "완료"; failed = "실패"; stopped = "중지됨"; idle = "유휴"
            endpoint = "T3 엔드포인트"; pairingCode = "일회용 페어링 코드"; connect = "연결"; disconnect = "연결 해제"
            pairHelp = "T3 Code에서 읽기 전용 임시 코드를 만드세요: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "로컬 또는 신뢰할 수 있는 원격 HTTPS 엔드포인트를 사용하세요. Vorssaint는 스레드 상태만 읽습니다."
            notConnected = "연결되지 않음"; connecting = "연결 중"; connected = "연결됨"; reconnecting = "다시 연결 중"
            needsPairing = "읽기 권한을 복원하려면 다시 페어링하세요"; unavailable = "T3 엔드포인트에 연결할 수 없음"
            workingCount = { "\($0)개 작업 중" }; errors = { Self.localizedError($0, language: language) }
        case .uk:
            source = "T3 Code"; working = "працює"; waiting = "очікує"; waitingInput = "очікує на введення"
            approval = "потрібне підтвердження"; completed = "завершено"; failed = "помилка"; stopped = "зупинено"; idle = "без роботи"
            endpoint = "Адреса T3"; pairingCode = "Одноразовий код сполучення"; connect = "Підключити"; disconnect = "Відключити"
            pairHelp = "Створіть тимчасовий код лише для читання в T3 Code: t3 pair --ttl 5m --label Vorssaint."
            remoteHelp = "Вкажіть локальну або довірену віддалену HTTPS-адресу. Vorssaint читає лише стан потоків."
            notConnected = "Немає підключення"; connecting = "Підключення"; connected = "Підключено"; reconnecting = "Повторне підключення"
            needsPairing = "Повторіть сполучення для відновлення доступу"; unavailable = "Адреса T3 недоступна"
            workingCount = { "\($0) працює" }; errors = { Self.localizedError($0, language: language) }
        case .zhHans:
            source = "T3 Code"; working = "运行中"; waiting = "等待中"; waitingInput = "等待输入"
            approval = "需要批准"; completed = "已完成"; failed = "失败"; stopped = "已停止"; idle = "空闲"
            endpoint = "T3 端点"; pairingCode = "一次性配对码"; connect = "连接"; disconnect = "断开连接"
            pairHelp = "在 T3 Code 中创建短时只读代码：t3 pair --ttl 5m --label Vorssaint。"
            remoteHelp = "使用本地或可信的远程 HTTPS 端点。Vorssaint 仅读取线程状态。"
            notConnected = "未连接"; connecting = "正在连接"; connected = "已连接"; reconnecting = "正在重新连接"
            needsPairing = "请重新配对以恢复读取权限"; unavailable = "无法连接 T3 端点"
            workingCount = { "\($0) 个运行中" }; errors = { Self.localizedError($0, language: language) }
        case .zhTW, .zhHK:
            source = "T3 Code"; working = "執行中"; waiting = "等待中"; waitingInput = "等待輸入"
            approval = "需要核准"; completed = "已完成"; failed = "失敗"; stopped = "已停止"; idle = "閒置"
            endpoint = "T3 端點"; pairingCode = "一次性配對碼"; connect = "連線"; disconnect = "中斷連線"
            pairHelp = "在 T3 Code 中建立短效唯讀代碼：t3 pair --ttl 5m --label Vorssaint。"
            remoteHelp = "使用本機或可信任的遠端 HTTPS 端點。Vorssaint 僅讀取執行緒狀態。"
            notConnected = "未連線"; connecting = "正在連線"; connected = "已連線"; reconnecting = "正在重新連線"
            needsPairing = "請重新配對以恢復讀取權限"; unavailable = "無法連線至 T3 端點"
            workingCount = { "\($0) 個執行中" }; errors = { Self.localizedError($0, language: language) }
        }
    }

    var statusText: (T3CodeConnectionState) -> String {
        { state in
            switch state {
            case .notConfigured: notConnected
            case .connecting: connecting
            case .connected: connected
            case .reconnecting: reconnecting
            case .needsPairing: needsPairing
            case .unavailable: unavailable
            }
        }
    }

    var stateText: (T3ThreadState) -> String {
        { state in
            switch state {
            case .working: working
            case .waiting: waiting
            case .waitingForInput: waitingInput
            case .waitingForApproval: approval
            case .idle: idle
            case .completed: completed
            case .failed: failed
            case .stopped: stopped
            }
        }
    }

    private static func englishError(_ error: T3CodeConnectionError) -> String {
        return switch error {
        case .invalidEndpoint: "Enter a valid local HTTP or remote HTTPS endpoint."
        case .unsupportedServer: "This T3 endpoint does not support orchestration protocol 2."
        case .pairingRejected: "The pairing code was rejected or has expired."
        case .readPermissionMissing: "T3 did not grant read-only orchestration access."
        case .authenticationExpired: "The T3 read-access token expired. Pair again."
        case .serverUnavailable: "Could not reach the T3 endpoint."
        case .invalidResponse: "T3 returned an unexpected response."
        }
    }

    private static func portugueseError(_ error: T3CodeConnectionError) -> String {
        switch error {
        case .invalidEndpoint: "Insira um endpoint HTTP local ou HTTPS remoto válido."
        case .unsupportedServer: "Este endpoint T3 não oferece suporte ao protocolo de orquestração 2."
        case .pairingRejected: "O código de pareamento foi recusado ou expirou."
        case .readPermissionMissing: "O T3 não concedeu acesso de orquestração somente para leitura."
        case .authenticationExpired: "O token de leitura do T3 expirou. Pareie novamente."
        case .serverUnavailable: "Não foi possível acessar o endpoint do T3."
        case .invalidResponse: "O T3 retornou uma resposta inesperada."
        }
    }

    private static func localizedError(_ error: T3CodeConnectionError, language: AppLanguage) -> String {
        let invalidEndpoint: String
        let pairing: String
        let unavailable: String
        switch language {
        case .enUS:
            return englishError(error)
        case .ptBR:
            return portugueseError(error)
        case .tr:
            invalidEndpoint = "Yerel HTTP veya uzak HTTPS adresi kullanın."
            pairing = "Salt okunur erişimi geri yüklemek için T3 ile yeniden eşleştirin."
            unavailable = "T3 uç noktası kullanılamıyor veya protokol yanıtı geçersiz."
        case .ru:
            invalidEndpoint = "Укажите локальный HTTP-адрес или удалённый HTTPS-адрес."
            pairing = "Повторите сопряжение с T3, чтобы восстановить доступ на чтение."
            unavailable = "Адрес T3 недоступен или вернул неверный ответ."
        case .es:
            invalidEndpoint = "Usa una dirección HTTP local o HTTPS remota."
            pairing = "Vuelve a emparejar con T3 para restaurar el acceso de lectura."
            unavailable = "La dirección de T3 no está disponible o devolvió una respuesta no válida."
        case .sk:
            invalidEndpoint = "Použite lokálnu HTTP alebo vzdialenú HTTPS adresu."
            pairing = "Znova spárujte T3, aby ste obnovili prístup na čítanie."
            unavailable = "Adresa T3 nie je dostupná alebo vrátila neplatnú odpoveď."
        case .de:
            invalidEndpoint = "Verwende eine lokale HTTP- oder entfernte HTTPS-Adresse."
            pairing = "Kopple T3 erneut, um den Lesezugriff wiederherzustellen."
            unavailable = "Der T3-Endpunkt ist nicht erreichbar oder lieferte eine ungültige Antwort."
        case .fr:
            invalidEndpoint = "Utilisez une adresse HTTP locale ou HTTPS distante."
            pairing = "Associez de nouveau T3 pour rétablir l’accès en lecture."
            unavailable = "L’adresse T3 est indisponible ou a renvoyé une réponse invalide."
        case .it:
            invalidEndpoint = "Usa un indirizzo HTTP locale o HTTPS remoto."
            pairing = "Associa di nuovo T3 per ripristinare l’accesso in lettura."
            unavailable = "L’endpoint T3 non è disponibile o ha restituito una risposta non valida."
        case .ja:
            invalidEndpoint = "ローカル HTTP またはリモート HTTPS アドレスを使用してください。"
            pairing = "読み取りアクセスを復元するには T3 と再ペアリングしてください。"
            unavailable = "T3 エンドポイントに接続できないか、応答が無効です。"
        case .ko:
            invalidEndpoint = "로컬 HTTP 또는 원격 HTTPS 주소를 사용하세요."
            pairing = "읽기 권한을 복원하려면 T3와 다시 페어링하세요."
            unavailable = "T3 엔드포인트에 연결할 수 없거나 응답이 올바르지 않습니다."
        case .uk:
            invalidEndpoint = "Вкажіть локальну HTTP- або віддалену HTTPS-адресу."
            pairing = "Повторіть сполучення з T3, щоб відновити доступ на читання."
            unavailable = "Адреса T3 недоступна або повернула некоректну відповідь."
        case .zhHans:
            invalidEndpoint = "请使用本地 HTTP 或远程 HTTPS 地址。"
            pairing = "请与 T3 重新配对以恢复读取权限。"
            unavailable = "T3 端点不可用或返回了无效响应。"
        case .zhTW, .zhHK:
            invalidEndpoint = "請使用本機 HTTP 或遠端 HTTPS 位址。"
            pairing = "請與 T3 重新配對以恢復讀取權限。"
            unavailable = "T3 端點無法使用或回傳了無效回應。"
        }
        return switch error {
        case .invalidEndpoint: invalidEndpoint
        case .pairingRejected, .readPermissionMissing, .authenticationExpired: pairing
        case .unsupportedServer, .serverUnavailable, .invalidResponse: unavailable
        }
    }
}
