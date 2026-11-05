// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Claude's plan beside the API key that pays for Claude Code.
struct ClaudeBillingStrings {
    /// The card's two halves.
    let subscription: String
    let api: String
    let thisMonth: String
    let credits: String
    /// Under the plan's half when the account check has no limits to show.
    let noLimits: String
    /// In the credits' place while no balance is entered, or after it is too old to follow.
    let addCredits: String
    let billingTitle: String
    let billsTo: String
    let automaticFormat: String
    let apiKey: String
    let billingCaption: String
    let creditsTitle: String
    let balance: String
    let save: String
    let clear: String
    let creditsCaption: String
    let creditsLeftFormat: String

    func automatic(_ detected: String) -> String { String(format: automaticFormat, detected) }
    func creditsLeft(_ amount: String, since: String) -> String { String(format: creditsLeftFormat, amount, since) }

    func billing(_ billing: AgentClaudeBilling, detectedAPI: Bool) -> String {
        switch billing {
        case .automatic: return automatic(detectedAPI ? apiKey : subscription)
        case .api: return apiKey
        case .subscription: return subscription
        }
    }
}

extension FeatureStrings {
    static func claudeBilling(_ language: AppLanguage) -> ClaudeBillingStrings {
        switch language {
        case .enUS: return ClaudeBillingStrings(
            subscription: "Subscription",
            api: "API",
            thisMonth: "This month",
            credits: "Available Credits",
            noLimits: "Sign in to Claude Code with your plan to see its limits.",
            addCredits: "Add your balance in Settings",
            billingTitle: "Claude billing",
            billsTo: "Claude Code bills",
            automaticFormat: "Automatic (%@)",
            apiKey: "API key",
            billingCaption: "With an API key, Claude Code’s spending shows apart from your plan. The plan’s limits come from your claude.ai sign-in and count your Claude app chats too; every terminal session is paid from your API credits.",
            creditsTitle: "API credits",
            balance: "Balance (USD)",
            save: "Save",
            clear: "Clear",
            creditsCaption: "Anthropic doesn’t share the balance with apps. Enter it from the Claude Console after each top-up; Claude Code’s spending since is taken from it at API list prices.",
            creditsLeftFormat: "%1$@ left · entered %2$@")
        case .ptBR: return ClaudeBillingStrings(
            subscription: "Assinatura",
            api: "API",
            thisMonth: "Este mês",
            credits: "Créditos",
            noLimits: "Entre no Claude Code com o seu plano para ver os limites.",
            addCredits: "Adicione o saldo nos Ajustes",
            billingTitle: "Cobrança do Claude",
            billsTo: "Claude Code cobra de",
            automaticFormat: "Automático (%@)",
            apiKey: "Chave de API",
            billingCaption: "Com uma chave de API, os gastos do Claude Code aparecem separados do plano. Os limites do plano vêm do seu login no claude.ai e contam também as conversas no app Claude; cada sessão no terminal é paga com os créditos da API.",
            creditsTitle: "Créditos da API",
            balance: "Saldo (USD)",
            save: "Salvar",
            clear: "Limpar",
            creditsCaption: "A Anthropic não informa o saldo a outros apps. Digite-o a partir do Claude Console após cada recarga; os gastos do Claude Code desde então são descontados pelos preços de tabela da API.",
            creditsLeftFormat: "Restam %1$@ · informado %2$@")
        case .es: return ClaudeBillingStrings(
            subscription: "Suscripción",
            api: "API",
            thisMonth: "Este mes",
            credits: "Créditos",
            noLimits: "Inicia sesión en Claude Code con tu plan para ver sus límites.",
            addCredits: "Añade tu saldo en Ajustes",
            billingTitle: "Facturación de Claude",
            billsTo: "Claude Code factura a",
            automaticFormat: "Automático (%@)",
            apiKey: "Clave de API",
            billingCaption: "Con una clave de API, el gasto de Claude Code se muestra aparte de tu plan. Los límites del plan vienen de tu sesión en claude.ai e incluyen también los chats de la app Claude; cada sesión del terminal se paga con tus créditos de la API.",
            creditsTitle: "Créditos de la API",
            balance: "Saldo (USD)",
            save: "Guardar",
            clear: "Borrar",
            creditsCaption: "Anthropic no comparte el saldo con otras apps. Introdúcelo desde la Claude Console tras cada recarga; el gasto de Claude Code desde entonces se descuenta a precios de lista de la API.",
            creditsLeftFormat: "Quedan %1$@ · introducido %2$@")
        case .sk: return ClaudeBillingStrings(
            subscription: "Predplatné",
            api: "API",
            thisMonth: "Tento mesiac",
            credits: "Kredity",
            noLimits: "Prihláste sa do Claude Code so svojím plánom, aby ste videli jeho limity.",
            addCredits: "Zadajte zostatok v Nastaveniach",
            billingTitle: "Platby za Claude",
            billsTo: "Claude Code účtuje na",
            automaticFormat: "Automaticky (%@)",
            apiKey: "Kľúč API",
            billingCaption: "S kľúčom API sa útrata Claude Code zobrazuje oddelene od plánu. Limity plánu pochádzajú z vášho prihlásenia na claude.ai a zahŕňajú aj konverzácie v aplikácii Claude; každá relácia v termináli sa platí z kreditov API.",
            creditsTitle: "Kredity API",
            balance: "Zostatok (USD)",
            save: "Uložiť",
            clear: "Vymazať",
            creditsCaption: "Anthropic zostatok iným aplikáciám neposkytuje. Zadajte ho z Claude Console po každom dobití; útrata Claude Code odvtedy sa od neho odpočíta podľa cenníka API.",
            creditsLeftFormat: "Zostáva %1$@ · zadané %2$@")
        case .de: return ClaudeBillingStrings(
            subscription: "Abo",
            api: "API",
            thisMonth: "Dieser Monat",
            credits: "Guthaben",
            noLimits: "Melde dich in Claude Code mit deinem Plan an, um seine Limits zu sehen.",
            addCredits: "Guthaben in den Einstellungen eintragen",
            billingTitle: "Claude-Abrechnung",
            billsTo: "Claude Code rechnet ab über",
            automaticFormat: "Automatisch (%@)",
            apiKey: "API-Schlüssel",
            billingCaption: "Mit einem API-Schlüssel erscheinen die Kosten von Claude Code getrennt von deinem Plan. Die Limits des Plans kommen aus deiner Anmeldung bei claude.ai und zählen auch Chats in der Claude-App; jede Terminal-Sitzung wird aus deinem API-Guthaben bezahlt.",
            creditsTitle: "API-Guthaben",
            balance: "Guthaben (USD)",
            save: "Sichern",
            clear: "Löschen",
            creditsCaption: "Anthropic teilt das Guthaben nicht mit Apps. Trage es nach jeder Aufladung aus der Claude Console ein; die Kosten von Claude Code seitdem werden zu API-Listenpreisen abgezogen.",
            creditsLeftFormat: "%1$@ übrig · eingetragen %2$@")
        case .fr: return ClaudeBillingStrings(
            subscription: "Abonnement",
            api: "API",
            thisMonth: "Ce mois-ci",
            credits: "Crédits",
            noLimits: "Connectez-vous à Claude Code avec votre forfait pour voir ses limites.",
            addCredits: "Ajoutez votre solde dans les Réglages",
            billingTitle: "Facturation Claude",
            billsTo: "Claude Code facture",
            automaticFormat: "Automatique (%@)",
            apiKey: "Clé d’API",
            billingCaption: "Avec une clé d’API, les dépenses de Claude Code s’affichent à part de votre forfait. Les limites du forfait viennent de votre connexion à claude.ai et comptent aussi les conversations de l’app Claude ; chaque session du terminal est payée avec vos crédits d’API.",
            creditsTitle: "Crédits d’API",
            balance: "Solde (USD)",
            save: "Enregistrer",
            clear: "Effacer",
            creditsCaption: "Anthropic ne communique pas le solde aux apps. Saisissez-le depuis la Claude Console après chaque recharge ; les dépenses de Claude Code depuis en sont déduites au prix catalogue de l’API.",
            creditsLeftFormat: "%1$@ restants · saisi %2$@")
        case .it: return ClaudeBillingStrings(
            subscription: "Abbonamento",
            api: "API",
            thisMonth: "Questo mese",
            credits: "Crediti",
            noLimits: "Accedi a Claude Code con il tuo piano per vederne i limiti.",
            addCredits: "Aggiungi il saldo nelle Impostazioni",
            billingTitle: "Fatturazione Claude",
            billsTo: "Claude Code addebita su",
            automaticFormat: "Automatico (%@)",
            apiKey: "Chiave API",
            billingCaption: "Con una chiave API, la spesa di Claude Code appare separata dal piano. I limiti del piano vengono dal tuo accesso a claude.ai e contano anche le chat nell’app Claude; ogni sessione nel terminale è pagata con i crediti API.",
            creditsTitle: "Crediti API",
            balance: "Saldo (USD)",
            save: "Salva",
            clear: "Cancella",
            creditsCaption: "Anthropic non comunica il saldo alle app. Inseriscilo dalla Claude Console dopo ogni ricarica; la spesa di Claude Code da allora viene sottratta ai prezzi di listino dell’API.",
            creditsLeftFormat: "%1$@ rimasti · inserito %2$@")
        case .ru: return ClaudeBillingStrings(
            subscription: "Подписка",
            api: "API",
            thisMonth: "Этот месяц",
            credits: "Кредиты",
            noLimits: "Войдите в Claude Code со своим тарифом, чтобы видеть его лимиты.",
            addCredits: "Укажите баланс в Настройках",
            billingTitle: "Оплата Claude",
            billsTo: "Claude Code оплачивается через",
            automaticFormat: "Автоматически (%@)",
            apiKey: "Ключ API",
            billingCaption: "С ключом API расходы Claude Code показываются отдельно от тарифа. Лимиты тарифа берутся из вашего входа на claude.ai и учитывают также чаты в приложении Claude; каждый сеанс в терминале оплачивается кредитами API.",
            creditsTitle: "Кредиты API",
            balance: "Баланс (USD)",
            save: "Сохранить",
            clear: "Очистить",
            creditsCaption: "Anthropic не сообщает баланс приложениям. Вводите его из Claude Console после каждого пополнения; расходы Claude Code с этого момента вычитаются по прейскуранту API.",
            creditsLeftFormat: "Осталось %1$@ · указано %2$@")
        case .tr: return ClaudeBillingStrings(
            subscription: "Abonelik",
            api: "API",
            thisMonth: "Bu ay",
            credits: "Krediler",
            noLimits: "Sınırlarını görmek için Claude Code’a planınızla giriş yapın.",
            addCredits: "Bakiyenizi Ayarlar’dan ekleyin",
            billingTitle: "Claude faturalandırması",
            billsTo: "Claude Code’un ödeme yolu",
            automaticFormat: "Otomatik (%@)",
            apiKey: "API anahtarı",
            billingCaption: "API anahtarıyla Claude Code harcaması planınızdan ayrı gösterilir. Planın sınırları claude.ai oturumunuzdan gelir ve Claude uygulamasındaki sohbetleri de sayar; her terminal oturumu API kredilerinizden ödenir.",
            creditsTitle: "API kredileri",
            balance: "Bakiye (USD)",
            save: "Kaydet",
            clear: "Temizle",
            creditsCaption: "Anthropic bakiyeyi uygulamalarla paylaşmaz. Her yüklemeden sonra Claude Console’dan girin; o zamandan beri Claude Code harcaması API liste fiyatlarıyla bundan düşülür.",
            creditsLeftFormat: "%1$@ kaldı · %2$@ girildi")
        case .ja: return ClaudeBillingStrings(
            subscription: "サブスクリプション",
            api: "API",
            thisMonth: "今月",
            credits: "クレジット",
            noLimits: "制限を表示するには、プランで Claude Code にサインインしてください。",
            addCredits: "設定で残高を入力",
            billingTitle: "Claude の請求",
            billsTo: "Claude Code の支払い",
            automaticFormat: "自動（%@）",
            apiKey: "API キー",
            billingCaption: "API キーを使うと、Claude Code の支出はプランとは別に表示されます。プランの制限は claude.ai のサインインから取得され、Claude アプリのチャットも含みます。ターミナルの各セッションは API クレジットから支払われます。",
            creditsTitle: "API クレジット",
            balance: "残高（USD）",
            save: "保存",
            clear: "消去",
            creditsCaption: "Anthropic は残高をアプリに提供していません。チャージのたびに Claude Console の残高を入力してください。それ以降の Claude Code の支出は API の定価で差し引かれます。",
            creditsLeftFormat: "残り %1$@ · %2$@に入力")
        case .ko: return ClaudeBillingStrings(
            subscription: "구독",
            api: "API",
            thisMonth: "이번 달",
            credits: "크레딧",
            noLimits: "한도를 보려면 요금제 계정으로 Claude Code에 로그인하세요.",
            addCredits: "설정에서 잔액 입력",
            billingTitle: "Claude 결제",
            billsTo: "Claude Code 결제 방식",
            automaticFormat: "자동(%@)",
            apiKey: "API 키",
            billingCaption: "API 키를 사용하면 Claude Code 지출이 요금제와 따로 표시됩니다. 요금제 한도는 claude.ai 로그인에서 가져오며 Claude 앱 채팅도 포함합니다. 터미널의 모든 세션은 API 크레딧으로 결제됩니다.",
            creditsTitle: "API 크레딧",
            balance: "잔액(USD)",
            save: "저장",
            clear: "지우기",
            creditsCaption: "Anthropic은 잔액을 앱에 알려 주지 않습니다. 충전할 때마다 Claude Console의 잔액을 입력하세요. 그 이후의 Claude Code 지출은 API 정가로 차감됩니다.",
            creditsLeftFormat: "%1$@ 남음 · %2$@ 입력")
        case .uk: return ClaudeBillingStrings(
            subscription: "Підписка",
            api: "API",
            thisMonth: "Цей місяць",
            credits: "Кредити",
            noLimits: "Увійдіть у Claude Code зі своїм тарифом, щоб бачити його ліміти.",
            addCredits: "Укажіть баланс у Параметрах",
            billingTitle: "Оплата Claude",
            billsTo: "Claude Code оплачується через",
            automaticFormat: "Автоматично (%@)",
            apiKey: "Ключ API",
            billingCaption: "З ключем API витрати Claude Code показуються окремо від тарифу. Ліміти тарифу беруться з вашого входу на claude.ai і враховують також чати в застосунку Claude; кожен сеанс у терміналі оплачується кредитами API.",
            creditsTitle: "Кредити API",
            balance: "Баланс (USD)",
            save: "Зберегти",
            clear: "Очистити",
            creditsCaption: "Anthropic не повідомляє баланс застосункам. Вводьте його з Claude Console після кожного поповнення; витрати Claude Code відтоді віднімаються за прейскурантом API.",
            creditsLeftFormat: "Залишилося %1$@ · указано %2$@")
        case .zhHans: return ClaudeBillingStrings(
            subscription: "订阅",
            api: "API",
            thisMonth: "本月",
            credits: "额度",
            noLimits: "使用你的套餐登录 Claude Code 以查看其限制。",
            addCredits: "在设置中填写余额",
            billingTitle: "Claude 计费",
            billsTo: "Claude Code 计费方式",
            automaticFormat: "自动（%@）",
            apiKey: "API 密钥",
            billingCaption: "使用 API 密钥时，Claude Code 的花费会与套餐分开显示。套餐限制来自你的 claude.ai 登录，也包括 Claude App 中的对话；每个终端会话都从 API 额度中支付。",
            creditsTitle: "API 额度",
            balance: "余额（美元）",
            save: "保存",
            clear: "清除",
            creditsCaption: "Anthropic 不会向 App 提供余额。每次充值后从 Claude Console 填写余额；此后 Claude Code 的花费会按 API 标价从中扣除。",
            creditsLeftFormat: "剩余 %1$@ · %2$@填写")
        case .zhTW: return ClaudeBillingStrings(
            subscription: "訂閱",
            api: "API",
            thisMonth: "本月",
            credits: "額度",
            noLimits: "使用你的方案登入 Claude Code 以查看其限制。",
            addCredits: "在設定中輸入餘額",
            billingTitle: "Claude 計費",
            billsTo: "Claude Code 計費方式",
            automaticFormat: "自動（%@）",
            apiKey: "API 金鑰",
            billingCaption: "使用 API 金鑰時，Claude Code 的花費會與方案分開顯示。方案限制來自你的 claude.ai 登入，也包含 Claude App 中的對話；每個終端機工作階段都從 API 額度支付。",
            creditsTitle: "API 額度",
            balance: "餘額（美元）",
            save: "儲存",
            clear: "清除",
            creditsCaption: "Anthropic 不會向 App 提供餘額。每次儲值後從 Claude Console 輸入餘額；之後 Claude Code 的花費會依 API 牌價從中扣除。",
            creditsLeftFormat: "剩餘 %1$@ · %2$@輸入")
        case .zhHK: return ClaudeBillingStrings(
            subscription: "訂閱",
            api: "API",
            thisMonth: "本月",
            credits: "額度",
            noLimits: "使用你的計劃登入 Claude Code 以查看其限制。",
            addCredits: "在設定中輸入餘額",
            billingTitle: "Claude 計費",
            billsTo: "Claude Code 計費方式",
            automaticFormat: "自動（%@）",
            apiKey: "API 密鑰",
            billingCaption: "使用 API 密鑰時，Claude Code 的花費會與計劃分開顯示。計劃限制來自你的 claude.ai 登入，亦包括 Claude App 中的對話；每個終端機工作階段都從 API 額度支付。",
            creditsTitle: "API 額度",
            balance: "餘額（美元）",
            save: "儲存",
            clear: "清除",
            creditsCaption: "Anthropic 不會向 App 提供餘額。每次增值後從 Claude Console 輸入餘額；之後 Claude Code 的花費會按 API 牌價從中扣除。",
            creditsLeftFormat: "剩餘 %1$@ · %2$@輸入")
        }
    }
}
