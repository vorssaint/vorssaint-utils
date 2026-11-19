// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct KimiAccountStrings {
    let title: String
    let explanation: String
    let region: String
    let china: String
    let international: String
    let notConfigured: String
    let check: String
    let refreshHint: String
    let expiredCredential: String
    let unauthorized: String
    let unavailable: String
    let invalidResponse: String
    let cliNote: String

    var cliAccount: String { "Kimi Code CLI" }

    func failure(_ failure: KimiUsageError) -> String {
        switch failure {
        case .expiredCredential: return expiredCredential
        case .unauthorized: return unauthorized
        case .unavailable, .cancelled: return unavailable
        case .invalidResponse: return invalidResponse
        }
    }
}

extension FeatureStrings {
    static func kimiAccount(_ language: AppLanguage) -> KimiAccountStrings {
        switch language {
        case .enUS: return KimiAccountStrings(
            title: "Kimi Code limits",
            explanation: "Reads your 5-hour, weekly and monthly Kimi Code allowances. Only quota metadata is requested; no prompt is sent to a model.",
            region: "Region", china: "China", international: "International",
            notConfigured: "Sign in to Kimi Code CLI to see plan limits.",
            check: "Check limits",
            refreshHint: "Refresh to check your Kimi Code limits.",
            expiredCredential: "Open Kimi Code CLI and sign in again to refresh its local authorization.",
            unauthorized: "Kimi rejected this credential. Check the CLI sign-in and region, then try again.",
            unavailable: "Could not check Kimi Code limits. Try again later.",
            invalidResponse: "Kimi returned usage data Vorssaint could not read.",
            cliNote: "Using your existing Kimi Code CLI sign-in.")
        case .ptBR: return KimiAccountStrings(
            title: "Limites do Kimi Code",
            explanation: "Lê suas cotas do Kimi Code de 5 horas, semanais e mensais. Apenas metadados de cota são solicitados; nenhum prompt é enviado ao modelo.",
            region: "Região", china: "China", international: "Internacional",
            notConfigured: "Entre no Kimi Code CLI para ver os limites do plano.",
            check: "Verificar limites",
            refreshHint: "Atualize para verificar seus limites do Kimi Code.",
            expiredCredential: "Abra o Kimi Code CLI e entre novamente para renovar a autorização local.",
            unauthorized: "O Kimi rejeitou esta credencial. Verifique o login do CLI e a região e tente novamente.",
            unavailable: "Não foi possível verificar os limites do Kimi Code. Tente novamente mais tarde.",
            invalidResponse: "O Kimi retornou dados de uso que o Vorssaint não conseguiu ler.",
            cliNote: "Usando seu login existente no Kimi Code CLI.")
        case .tr: return KimiAccountStrings(
            title: "Kimi Code sınırları",
            explanation: "Kimi Code’un 5 saatlik, haftalık ve aylık kotalarını okur. Yalnızca kota meta verileri istenir; modele istem gönderilmez.",
            region: "Bölge", china: "Çin", international: "Uluslararası",
            notConfigured: "Plan sınırlarını görmek için Kimi Code CLI’da oturum açın.",
            check: "Sınırları denetle",
            refreshHint: "Kimi Code sınırlarınızı denetlemek için yenileyin.",
            expiredCredential: "Yerel yetkilendirmeyi yenilemek için Kimi Code CLI’yı açıp yeniden oturum açın.",
            unauthorized: "Kimi bu kimlik bilgisini reddetti. CLI oturumunu ve bölgeyi kontrol edip yeniden deneyin.",
            unavailable: "Kimi Code sınırları denetlenemedi. Daha sonra yeniden deneyin.",
            invalidResponse: "Kimi, Vorssaint’in okuyamadığı kullanım verileri döndürdü.",
            cliNote: "Mevcut Kimi Code CLI oturumunuz kullanılıyor.")
        case .ru: return KimiAccountStrings(
            title: "Лимиты Kimi Code",
            explanation: "Показывает лимиты Kimi Code за 5 часов, неделю и месяц. Запрашиваются только сведения о квотах; запросы к модели не отправляются.",
            region: "Регион", china: "Китай", international: "Международный",
            notConfigured: "Войдите в Kimi Code CLI, чтобы видеть лимиты тарифа.",
            check: "Проверить лимиты",
            refreshHint: "Обновите, чтобы проверить лимиты Kimi Code.",
            expiredCredential: "Откройте Kimi Code CLI и войдите снова, чтобы обновить локальную авторизацию.",
            unauthorized: "Kimi отклонил эти данные авторизации. Проверьте вход в CLI и регион, затем попробуйте ещё раз.",
            unavailable: "Не удалось проверить лимиты Kimi Code. Попробуйте позже.",
            invalidResponse: "Kimi вернул данные об использовании, которые Vorssaint не смог прочитать.",
            cliNote: "Используется существующий вход в Kimi Code CLI.")
        case .es: return KimiAccountStrings(
            title: "Límites de Kimi Code",
            explanation: "Lee tus cuotas de Kimi Code de 5 horas, semanales y mensuales. Solo solicita metadatos de cuota; no envía instrucciones al modelo.",
            region: "Región", china: "China", international: "Internacional",
            notConfigured: "Inicia sesión en Kimi Code CLI para ver los límites del plan.",
            check: "Consultar límites",
            refreshHint: "Actualiza para consultar tus límites de Kimi Code.",
            expiredCredential: "Abre Kimi Code CLI e inicia sesión de nuevo para renovar la autorización local.",
            unauthorized: "Kimi rechazó esta credencial. Comprueba el inicio de sesión del CLI y la región e inténtalo de nuevo.",
            unavailable: "No se pudieron consultar los límites de Kimi Code. Inténtalo más tarde.",
            invalidResponse: "Kimi devolvió datos de uso que Vorssaint no pudo leer.",
            cliNote: "Se usa tu sesión existente de Kimi Code CLI.")
        case .sk: return KimiAccountStrings(
            title: "Limity Kimi Code",
            explanation: "Číta vaše 5-hodinové, týždenné a mesačné kvóty Kimi Code. Vyžadujú sa iba metadáta kvót; modelu sa neposiela žiadny prompt.",
            region: "Región", china: "Čína", international: "Medzinárodný",
            notConfigured: "Prihláste sa do Kimi Code CLI, aby sa zobrazili limity plánu.",
            check: "Skontrolovať limity",
            refreshHint: "Obnovte a skontrolujte limity Kimi Code.",
            expiredCredential: "Otvorte Kimi Code CLI a prihláste sa znova, aby sa obnovila lokálna autorizácia.",
            unauthorized: "Kimi tieto prihlasovacie údaje odmietol. Skontrolujte prihlásenie CLI a región a skúste to znova.",
            unavailable: "Limity Kimi Code sa nepodarilo skontrolovať. Skúste to neskôr.",
            invalidResponse: "Kimi vrátil údaje o využití, ktoré Vorssaint nedokázal prečítať.",
            cliNote: "Používa sa vaše existujúce prihlásenie do Kimi Code CLI.")
        case .de: return KimiAccountStrings(
            title: "Kimi-Code-Limits",
            explanation: "Liest deine 5-Stunden-, Wochen- und Monatskontingente für Kimi Code. Es werden nur Kontingentdaten abgefragt und kein Prompt an ein Modell gesendet.",
            region: "Region", china: "China", international: "International",
            notConfigured: "Melde dich bei Kimi Code CLI an, um Planlimits zu sehen.",
            check: "Limits prüfen",
            refreshHint: "Aktualisiere, um deine Kimi-Code-Limits zu prüfen.",
            expiredCredential: "Öffne Kimi Code CLI und melde dich erneut an, um die lokale Autorisierung zu erneuern.",
            unauthorized: "Kimi hat diese Anmeldedaten abgelehnt. Prüfe die CLI-Anmeldung und die Region und versuche es erneut.",
            unavailable: "Kimi-Code-Limits konnten nicht geprüft werden. Versuche es später erneut.",
            invalidResponse: "Kimi hat Nutzungsdaten zurückgegeben, die Vorssaint nicht lesen konnte.",
            cliNote: "Deine bestehende Kimi-Code-CLI-Anmeldung wird verwendet.")
        case .fr: return KimiAccountStrings(
            title: "Limites de Kimi Code",
            explanation: "Lit vos quotas Kimi Code sur 5 heures, une semaine et un mois. Seules les métadonnées de quota sont demandées ; aucune requête n’est envoyée au modèle.",
            region: "Région", china: "Chine", international: "International",
            notConfigured: "Connectez-vous à Kimi Code CLI pour voir les limites du forfait.",
            check: "Vérifier les limites",
            refreshHint: "Actualisez pour vérifier vos limites Kimi Code.",
            expiredCredential: "Ouvrez Kimi Code CLI et reconnectez-vous pour renouveler l’autorisation locale.",
            unauthorized: "Kimi a refusé ces identifiants. Vérifiez la connexion du CLI et la région, puis réessayez.",
            unavailable: "Impossible de vérifier les limites Kimi Code. Réessayez plus tard.",
            invalidResponse: "Kimi a renvoyé des données d’utilisation illisibles par Vorssaint.",
            cliNote: "Votre connexion existante à Kimi Code CLI est utilisée.")
        case .it: return KimiAccountStrings(
            title: "Limiti di Kimi Code",
            explanation: "Legge le quote di Kimi Code di 5 ore, settimanali e mensili. Richiede solo metadati sulle quote; non invia alcun prompt al modello.",
            region: "Area geografica", china: "Cina", international: "Internazionale",
            notConfigured: "Accedi a Kimi Code CLI per vedere i limiti del piano.",
            check: "Controlla limiti",
            refreshHint: "Aggiorna per controllare i limiti di Kimi Code.",
            expiredCredential: "Apri Kimi Code CLI e accedi di nuovo per rinnovare l’autorizzazione locale.",
            unauthorized: "Kimi ha rifiutato queste credenziali. Controlla l’accesso al CLI e l’area geografica, quindi riprova.",
            unavailable: "Impossibile controllare i limiti di Kimi Code. Riprova più tardi.",
            invalidResponse: "Kimi ha restituito dati di utilizzo che Vorssaint non ha potuto leggere.",
            cliNote: "Viene usato il tuo accesso esistente a Kimi Code CLI.")
        case .ja: return KimiAccountStrings(
            title: "Kimi Codeの上限",
            explanation: "Kimi Codeの5時間・週間・月間クォータを読み取ります。クォータのメタデータだけを取得し、モデルへプロンプトは送信しません。",
            region: "地域", china: "中国", international: "インターナショナル",
            notConfigured: "Kimi Code CLIにサインインしてプランの上限を表示してください。",
            check: "上限を確認",
            refreshHint: "更新してKimi Codeの上限を確認します。",
            expiredCredential: "Kimi Code CLIを開いて再度サインインし、ローカル認証を更新してください。",
            unauthorized: "Kimiがこの認証情報を拒否しました。CLIのサインインと地域を確認して再試行してください。",
            unavailable: "Kimi Codeの上限を確認できませんでした。あとで再試行してください。",
            invalidResponse: "Kimiから、Vorssaintが読み取れない使用データが返されました。",
            cliNote: "既存のKimi Code CLIサインインを使用しています。")
        case .ko: return KimiAccountStrings(
            title: "Kimi Code 한도",
            explanation: "Kimi Code의 5시간, 주간 및 월간 할당량을 읽습니다. 할당량 메타데이터만 요청하며 모델에 프롬프트를 전송하지 않습니다.",
            region: "지역", china: "중국", international: "인터내셔널",
            notConfigured: "Kimi Code CLI에 로그인하여 플랜 한도를 확인하세요.",
            check: "한도 확인",
            refreshHint: "새로고침하여 Kimi Code 한도를 확인하세요.",
            expiredCredential: "Kimi Code CLI를 열고 다시 로그인하여 로컬 인증을 갱신하세요.",
            unauthorized: "Kimi가 이 인증 정보를 거부했습니다. CLI 로그인과 지역을 확인한 후 다시 시도하세요.",
            unavailable: "Kimi Code 한도를 확인하지 못했습니다. 나중에 다시 시도하세요.",
            invalidResponse: "Kimi가 Vorssaint에서 읽을 수 없는 사용량 데이터를 반환했습니다.",
            cliNote: "기존 Kimi Code CLI 로그인을 사용합니다.")
        case .uk: return KimiAccountStrings(
            title: "Ліміти Kimi Code",
            explanation: "Показує ліміти Kimi Code за 5 годин, тиждень і місяць. Запитуються лише відомості про квоти; запити до моделі не надсилаються.",
            region: "Регіон", china: "Китай", international: "Міжнародний",
            notConfigured: "Увійдіть у Kimi Code CLI, щоб бачити ліміти тарифу.",
            check: "Перевірити ліміти",
            refreshHint: "Оновіть, щоб перевірити ліміти Kimi Code.",
            expiredCredential: "Відкрийте Kimi Code CLI й увійдіть знову, щоб оновити локальну авторизацію.",
            unauthorized: "Kimi відхилив ці дані авторизації. Перевірте вхід у CLI і регіон, потім спробуйте ще раз.",
            unavailable: "Не вдалося перевірити ліміти Kimi Code. Спробуйте пізніше.",
            invalidResponse: "Kimi повернув дані про використання, які Vorssaint не зміг прочитати.",
            cliNote: "Використовується наявний вхід у Kimi Code CLI.")
        case .zhHans: return KimiAccountStrings(
            title: "Kimi Code 限额",
            explanation: "读取 Kimi Code 的 5 小时、每周和每月配额。仅请求配额元数据，不会向模型发送提示词。",
            region: "地区", china: "中国", international: "国际",
            notConfigured: "登录 Kimi Code CLI 以查看套餐限额。",
            check: "检查限额",
            refreshHint: "刷新以检查你的 Kimi Code 限额。",
            expiredCredential: "请打开 Kimi Code CLI 并重新登录，以更新本地授权。",
            unauthorized: "Kimi 拒绝了此授权信息。请检查 CLI 登录状态和地区，然后重试。",
            unavailable: "无法检查 Kimi Code 限额。请稍后重试。",
            invalidResponse: "Kimi 返回了 Vorssaint 无法读取的使用数据。",
            cliNote: "正在使用你现有的 Kimi Code CLI 登录状态。")
        case .zhTW: return KimiAccountStrings(
            title: "Kimi Code 限額",
            explanation: "讀取 Kimi Code 的 5 小時、每週和每月配額。僅請求配額中繼資料，不會向模型傳送提示詞。",
            region: "地區", china: "中國", international: "國際",
            notConfigured: "登入 Kimi Code CLI 以查看方案限額。",
            check: "檢查限額",
            refreshHint: "重新整理以檢查你的 Kimi Code 限額。",
            expiredCredential: "請開啟 Kimi Code CLI 並重新登入，以更新本機授權。",
            unauthorized: "Kimi 拒絕了此授權資料。請檢查 CLI 登入狀態和地區，然後重試。",
            unavailable: "無法檢查 Kimi Code 限額。請稍後重試。",
            invalidResponse: "Kimi 回傳了 Vorssaint 無法讀取的使用資料。",
            cliNote: "正在使用你現有的 Kimi Code CLI 登入狀態。")
        case .zhHK: return KimiAccountStrings(
            title: "Kimi Code 限額",
            explanation: "讀取 Kimi Code 的 5 小時、每週和每月配額。只會請求配額元數據，不會向模型傳送提示詞。",
            region: "地區", china: "中國", international: "國際",
            notConfigured: "登入 Kimi Code CLI 以查看計劃限額。",
            check: "檢查限額",
            refreshHint: "重新整理以檢查你的 Kimi Code 限額。",
            expiredCredential: "請開啟 Kimi Code CLI 並重新登入，以更新本機授權。",
            unauthorized: "Kimi 拒絕了此授權資料。請檢查 CLI 登入狀態和地區，然後重試。",
            unavailable: "無法檢查 Kimi Code 限額。請稍後重試。",
            invalidResponse: "Kimi 回傳了 Vorssaint 無法讀取的使用資料。",
            cliNote: "正在使用你現有的 Kimi Code CLI 登入狀態。")
        }
    }
}
