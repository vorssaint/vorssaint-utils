// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClaudeAccountStrings {
    let accountsTitle: String
    let allAccounts: String
    let multipleExplanation: String
    let defaultAccount: String
    let invalidFolder: String
    let noLimits: String
    let signInHelp: String
}

extension FeatureStrings {
    static func claudeAccount(_ language: AppLanguage) -> ClaudeAccountStrings {
        switch language {
        case .enUS: return ClaudeAccountStrings(
            accountsTitle: "Claude accounts", allAccounts: "All accounts",
            multipleExplanation: "All listed profiles are monitored together. Choose an account on the AI page to see its usage, or All accounts for combined totals. The first account supplies the resting island’s limits and limit alerts. Accounts must already be signed in through Claude Code.",
            defaultAccount: "Default account", invalidFolder: "Choose an existing Claude Code profile folder that belongs to you and contains its own .claude.json file. The folder must not be writable by others, and the file must not be a link.",
            noLimits: "Claude Code has not returned limits for this account yet.",
            signInHelp: "How to sign in to another Claude account")
        case .ptBR: return ClaudeAccountStrings(
            accountsTitle: "Contas do Claude", allAccounts: "Todas as contas",
            multipleExplanation: "Todos os perfis listados são monitorados juntos. Escolha uma conta na página de IA para ver seu uso ou Todas as contas para os totais combinados. A primeira conta fornece os limites da ilha em repouso e os alertas de limite. As contas já devem estar conectadas pelo Claude Code.",
            defaultAccount: "Conta padrão", invalidFolder: "Escolha uma pasta de perfil do Claude Code que seja sua e contenha o próprio arquivo .claude.json. A pasta não pode permitir escrita por outros, e o arquivo não pode ser um link.",
            noLimits: "O Claude Code ainda não retornou os limites desta conta.",
            signInHelp: "Como entrar em outra conta do Claude")
        case .tr: return ClaudeAccountStrings(
            accountsTitle: "Claude hesapları", allAccounts: "Tüm hesaplar",
            multipleExplanation: "Listedeki tüm profiller birlikte izlenir. Kullanımı görmek için YZ sayfasında bir hesap, toplamları görmek için Tüm hesaplar seçin. İlk hesap, boşta olan adanın sınırlarını ve sınır uyarılarını sağlar. Hesaplarda Claude Code üzerinden oturum açılmış olmalıdır.",
            defaultAccount: "Varsayılan hesap", invalidFolder: "Size ait ve kendi .claude.json dosyasını içeren mevcut bir Claude Code profil klasörü seçin. Başkaları klasöre yazamamalı ve dosya bir bağlantı olmamalıdır.",
            noLimits: "Claude Code bu hesabın sınırlarını henüz bildirmedi.",
            signInHelp: "Başka bir Claude hesabında oturum açma")
        case .ru: return ClaudeAccountStrings(
            accountsTitle: "Аккаунты Claude", allAccounts: "Все аккаунты",
            multipleExplanation: "Все профили отслеживаются одновременно. Выберите аккаунт на странице ИИ для его статистики или Все аккаунты для общих итогов. Первый аккаунт определяет лимиты островка в покое и предупреждения о лимитах. В аккаунты нужно заранее войти через Claude Code.",
            defaultAccount: "Аккаунт по умолчанию", invalidFolder: "Выберите принадлежащую вам папку профиля Claude Code с собственным файлом .claude.json. Другие пользователи не должны иметь права записи в папку, а файл не должен быть ссылкой.",
            noLimits: "Claude Code ещё не получил лимиты этого аккаунта.",
            signInHelp: "Как войти в другой аккаунт Claude")
        case .es: return ClaudeAccountStrings(
            accountsTitle: "Cuentas de Claude", allAccounts: "Todas las cuentas",
            multipleExplanation: "Todos los perfiles se supervisan a la vez. Elija una cuenta en la página de IA para ver su uso o Todas las cuentas para los totales combinados. La primera cuenta proporciona los límites de la isla en reposo y las alertas. Las cuentas deben tener una sesión iniciada en Claude Code.",
            defaultAccount: "Cuenta predeterminada", invalidFolder: "Elija una carpeta de perfil de Claude Code que le pertenezca y contenga su propio archivo .claude.json. Otros usuarios no deben poder escribir en la carpeta y el archivo no debe ser un enlace.",
            noLimits: "Claude Code aún no ha devuelto los límites de esta cuenta.",
            signInHelp: "Cómo iniciar sesión en otra cuenta de Claude")
        case .sk: return ClaudeAccountStrings(
            accountsTitle: "Účty Claude", allAccounts: "Všetky účty",
            multipleExplanation: "Všetky uvedené profily sa sledujú súčasne. Na stránke AI vyberte účet pre jeho používanie alebo Všetky účty pre spoločné súčty. Prvý účet poskytuje limity ostrovčeka v pokoji a upozornenia na limity. Účty už musia byť prihlásené cez Claude Code.",
            defaultAccount: "Predvolený účet", invalidFolder: "Vyberte existujúci priečinok profilu Claude Code, ktorý vám patrí a obsahuje vlastný súbor .claude.json. Ostatní do priečinka nesmú zapisovať a súbor nesmie byť odkazom.",
            noLimits: "Claude Code zatiaľ nevrátil limity tohto účtu.",
            signInHelp: "Ako sa prihlásiť do iného účtu Claude")
        case .de: return ClaudeAccountStrings(
            accountsTitle: "Claude-Konten", allAccounts: "Alle Konten",
            multipleExplanation: "Alle aufgeführten Profile werden gleichzeitig überwacht. Wählen Sie auf der KI-Seite ein Konto für dessen Nutzung oder Alle Konten für die Gesamtsummen. Das erste Konto liefert die Limits der ruhenden Insel und die Limitwarnungen. Die Konten müssen bereits in Claude Code angemeldet sein.",
            defaultAccount: "Standardkonto", invalidFolder: "Wählen Sie einen vorhandenen Claude-Code-Profilordner, der Ihnen gehört und eine eigene .claude.json enthält. Andere dürfen nicht in den Ordner schreiben können, und die Datei darf keine Verknüpfung sein.",
            noLimits: "Claude Code hat die Limits dieses Kontos noch nicht abgerufen.",
            signInHelp: "Bei einem anderen Claude-Konto anmelden")
        case .fr: return ClaudeAccountStrings(
            accountsTitle: "Comptes Claude", allAccounts: "Tous les comptes",
            multipleExplanation: "Tous les profils sont suivis ensemble. Choisissez un compte sur la page IA pour voir son usage, ou Tous les comptes pour les totaux cumulés. Le premier compte fournit les limites de l’îlot au repos et les alertes. Les comptes doivent déjà être connectés dans Claude Code.",
            defaultAccount: "Compte par défaut", invalidFolder: "Choisissez un dossier de profil Claude Code existant qui vous appartient et contient son propre fichier .claude.json. Les autres utilisateurs ne doivent pas pouvoir écrire dans ce dossier et le fichier ne doit pas être un lien.",
            noLimits: "Claude Code n’a pas encore renvoyé les limites de ce compte.",
            signInHelp: "Comment se connecter à un autre compte Claude")
        case .it: return ClaudeAccountStrings(
            accountsTitle: "Account Claude", allAccounts: "Tutti gli account",
            multipleExplanation: "Tutti i profili sono monitorati insieme. Scelga un account nella pagina IA per vedere il suo utilizzo o Tutti gli account per i totali complessivi. Il primo account fornisce i limiti dell’isola a riposo e gli avvisi sui limiti. Gli account devono essere già connessi tramite Claude Code.",
            defaultAccount: "Account predefinito", invalidFolder: "Scelga una cartella di profilo Claude Code esistente di sua proprietà, con il proprio file .claude.json. Gli altri utenti non devono poter scrivere nella cartella e il file non deve essere un collegamento.",
            noLimits: "Claude Code non ha ancora restituito i limiti di questo account.",
            signInHelp: "Come accedere a un altro account Claude")
        case .ja: return ClaudeAccountStrings(
            accountsTitle: "Claudeアカウント", allAccounts: "すべてのアカウント",
            multipleExplanation: "一覧のすべてのプロファイルを同時に監視します。AIページでアカウントを選ぶと個別の使用量、すべてのアカウントを選ぶと合計が表示されます。待機中のアイランドの上限と上限通知には最初のアカウントを使用します。各アカウントは事前にClaude Codeでログインしてください。",
            defaultAccount: "デフォルトのアカウント", invalidFolder: "ご自身が所有し、独自の.claude.jsonファイルを含む既存のClaude Codeプロファイルフォルダを選択してください。他のユーザーが書き込めるフォルダや、リンクされたファイルは使用できません。",
            noLimits: "Claude Codeはまだこのアカウントの上限を返していません。",
            signInHelp: "別のClaudeアカウントにログインする方法")
        case .ko: return ClaudeAccountStrings(
            accountsTitle: "Claude 계정", allAccounts: "모든 계정",
            multipleExplanation: "목록의 모든 프로필을 함께 모니터링합니다. AI 페이지에서 계정을 선택하면 개별 사용량을, 모든 계정을 선택하면 합계를 볼 수 있습니다. 첫 번째 계정이 대기 중인 아일랜드의 한도와 한도 알림에 사용됩니다. 각 계정은 Claude Code에서 미리 로그인해야 합니다.",
            defaultAccount: "기본 계정", invalidFolder: "본인 소유이며 자체 .claude.json 파일이 있는 기존 Claude Code 프로필 폴더를 선택하세요. 다른 사용자가 폴더에 쓸 수 없어야 하며 파일은 링크가 아니어야 합니다.",
            noLimits: "Claude Code가 아직 이 계정의 한도를 반환하지 않았습니다.",
            signInHelp: "다른 Claude 계정에 로그인하는 방법")
        case .uk: return ClaudeAccountStrings(
            accountsTitle: "Облікові записи Claude", allAccounts: "Усі облікові записи",
            multipleExplanation: "Усі профілі відстежуються одночасно. Виберіть обліковий запис на сторінці ШІ для його статистики або Усі облікові записи для загальних підсумків. Перший запис визначає ліміти острівця в спокої та попередження. У записи потрібно заздалегідь увійти через Claude Code.",
            defaultAccount: "Типовий обліковий запис", invalidFolder: "Виберіть наявну папку профілю Claude Code, яка належить вам і містить власний файл .claude.json. Інші користувачі не повинні мати права запису в папку, а файл не повинен бути посиланням.",
            noLimits: "Claude Code ще не повернув ліміти цього облікового запису.",
            signInHelp: "Як увійти до іншого облікового запису Claude")
        case .zhHans: return ClaudeAccountStrings(
            accountsTitle: "Claude 账户", allAccounts: "所有账户",
            multipleExplanation: "同时监测列表中的所有配置。在 AI 页面选择账户可查看其用量，选择所有账户可查看合计。第一个账户提供灵动岛静止时的限额和限额提醒。各账户须已通过 Claude Code 登录。",
            defaultAccount: "默认账户", invalidFolder: "请选择属于您且包含独立 .claude.json 文件的现有 Claude Code 配置文件夹。其他用户不能具有该文件夹的写入权限，且该文件不能是链接。",
            noLimits: "Claude Code 尚未返回此账户的限额。",
            signInHelp: "如何登录另一个 Claude 账户")
        case .zhTW: return ClaudeAccountStrings(
            accountsTitle: "Claude 帳號", allAccounts: "所有帳號",
            multipleExplanation: "同時監測清單中的所有設定檔。在 AI 頁面選擇帳號可查看個別用量，選擇所有帳號可查看總計。第一個帳號提供動態島待機時的額度與額度提醒。各帳號須已透過 Claude Code 登入。",
            defaultAccount: "預設帳號", invalidFolder: "請選擇屬於您且包含獨立 .claude.json 檔案的現有 Claude Code 設定檔資料夾。其他使用者不可具有該資料夾的寫入權限，且該檔案不可為連結。",
            noLimits: "Claude Code 尚未傳回此帳號的額度。",
            signInHelp: "如何登入另一個 Claude 帳號")
        case .zhHK: return ClaudeAccountStrings(
            accountsTitle: "Claude 帳戶", allAccounts: "所有帳戶",
            multipleExplanation: "同時監察清單中的所有設定檔。在 AI 頁面選擇帳戶可查看個別用量，選擇所有帳戶可查看總計。第一個帳戶提供動態島待機時的限額及限額提示。各帳戶須已透過 Claude Code 登入。",
            defaultAccount: "預設帳戶", invalidFolder: "請選擇屬於您且包含獨立 .claude.json 檔案的現有 Claude Code 設定檔資料夾。其他使用者不可擁有該資料夾的寫入權限，檔案亦不可是連結。",
            noLimits: "Claude Code 尚未傳回此帳戶的限額。",
            signInHelp: "如何登入另一個 Claude 帳戶")
        }
    }
}
