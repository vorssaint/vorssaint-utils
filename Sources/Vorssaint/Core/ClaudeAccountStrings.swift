// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClaudeAccountStrings {
    let title: String
    let defaultAccount: String
    let chooseFolder: String
    let explanation: String
    let invalidFolder: String
    let unknownAccount: String
    let noLimits: String
    let signInHelp: String
}

extension FeatureStrings {
    static func claudeAccount(_ language: AppLanguage) -> ClaudeAccountStrings {
        switch language {
        case .enUS: return ClaudeAccountStrings(
            title: "Claude account", defaultAccount: "Default account", chooseFolder: "Choose account folder…",
            explanation: "Choose a profile already signed in to Claude Code. Usage comes from that profile’s sessions, and Claude Code checks its account’s limits. Changing this selection does not change the account in your other apps.",
            invalidFolder: "Choose an existing Claude Code profile folder that belongs to you and contains its own .claude.json file. The folder must not be writable by others, and the file must not be a link.",
            unknownAccount: "No account identified in this profile.",
            noLimits: "Claude Code has not returned limits for this account yet.",
            signInHelp: "How to sign in to another Claude account")
        case .ptBR: return ClaudeAccountStrings(
            title: "Conta do Claude", defaultAccount: "Conta padrão", chooseFolder: "Escolher pasta da conta…",
            explanation: "Escolha um perfil já conectado ao Claude Code. O uso vem das sessões desse perfil, e o Claude Code consulta os limites da conta. Essa escolha não altera a conta nos outros aplicativos.",
            invalidFolder: "Escolha uma pasta de perfil do Claude Code que seja sua e contenha o próprio arquivo .claude.json. A pasta não pode permitir escrita por outros, e o arquivo não pode ser um link.",
            unknownAccount: "Nenhuma conta identificada neste perfil.",
            noLimits: "O Claude Code ainda não retornou os limites desta conta.",
            signInHelp: "Como entrar em outra conta do Claude")
        case .tr: return ClaudeAccountStrings(
            title: "Claude hesabı", defaultAccount: "Varsayılan hesap", chooseFolder: "Hesap klasörünü seçin…",
            explanation: "Claude Code’da oturum açmış bir profil seçin. Kullanım bu profilin oturumlarından gelir; Claude Code hesabın sınırlarını denetler. Bu seçim diğer uygulamalardaki hesabı değiştirmez.",
            invalidFolder: "Size ait ve kendi .claude.json dosyasını içeren mevcut bir Claude Code profil klasörü seçin. Başkaları klasöre yazamamalı ve dosya bir bağlantı olmamalıdır.",
            unknownAccount: "Bu profilde hesap tanımlanamadı.", noLimits: "Claude Code bu hesabın sınırlarını henüz bildirmedi.",
            signInHelp: "Başka bir Claude hesabında oturum açma")
        case .ru: return ClaudeAccountStrings(
            title: "Аккаунт Claude", defaultAccount: "Аккаунт по умолчанию", chooseFolder: "Выбрать папку аккаунта…",
            explanation: "Выберите профиль с выполненным входом в Claude Code. Использование берётся из сеансов этого профиля, а Claude Code проверяет лимиты аккаунта. Выбор не меняет аккаунт в других приложениях.",
            invalidFolder: "Выберите принадлежащую вам папку профиля Claude Code с собственным файлом .claude.json. Другие пользователи не должны иметь права записи в папку, а файл не должен быть ссылкой.",
            unknownAccount: "В этом профиле аккаунт не определён.", noLimits: "Claude Code ещё не получил лимиты этого аккаунта.",
            signInHelp: "Как войти в другой аккаунт Claude")
        case .es: return ClaudeAccountStrings(
            title: "Cuenta de Claude", defaultAccount: "Cuenta predeterminada", chooseFolder: "Elegir carpeta de la cuenta…",
            explanation: "Elija un perfil que ya tenga una sesión iniciada en Claude Code. El uso procede de las sesiones de ese perfil y Claude Code consulta los límites de su cuenta. Esta selección no cambia la cuenta en otras aplicaciones.",
            invalidFolder: "Elija una carpeta de perfil de Claude Code que le pertenezca y contenga su propio archivo .claude.json. Otros usuarios no deben poder escribir en la carpeta y el archivo no debe ser un enlace.",
            unknownAccount: "No se ha identificado ninguna cuenta en este perfil.", noLimits: "Claude Code aún no ha devuelto los límites de esta cuenta.",
            signInHelp: "Cómo iniciar sesión en otra cuenta de Claude")
        case .sk: return ClaudeAccountStrings(
            title: "Účet Claude", defaultAccount: "Predvolený účet", chooseFolder: "Vybrať priečinok účtu…",
            explanation: "Vyberte profil, ktorý je už prihlásený do Claude Code. Používanie pochádza z relácií tohto profilu a Claude Code kontroluje limity jeho účtu. Tento výber nezmení účet v ostatných aplikáciách.",
            invalidFolder: "Vyberte existujúci priečinok profilu Claude Code, ktorý vám patrí a obsahuje vlastný súbor .claude.json. Ostatní do priečinka nesmú zapisovať a súbor nesmie byť odkazom.",
            unknownAccount: "V tomto profile nebol rozpoznaný žiadny účet.", noLimits: "Claude Code zatiaľ nevrátil limity tohto účtu.",
            signInHelp: "Ako sa prihlásiť do iného účtu Claude")
        case .cs: return ClaudeAccountStrings(
            title: "Účet Claude", defaultAccount: "Výchozí účet", chooseFolder: "Vybrat složku účtu…",
            explanation: "Vyberte profil, který je už přihlášený do Claude Code. Využití pochází z relací tohoto profilu a Claude Code kontroluje limity jeho účtu. Tento výběr nezmění účet v ostatních aplikacích.",
            invalidFolder: "Vyberte existující složku profilu Claude Code, která vám patří a obsahuje vlastní soubor .claude.json. Ostatní do složky nesmí zapisovat a soubor nesmí být odkazem.",
            unknownAccount: "V tomto profilu nebyl rozpoznán žádný účet.", noLimits: "Claude Code zatím nevrátil limity tohoto účtu.",
            signInHelp: "Jak se přihlásit k jinému účtu Claude")
        case .de: return ClaudeAccountStrings(
            title: "Claude-Konto", defaultAccount: "Standardkonto", chooseFolder: "Kontoordner auswählen…",
            explanation: "Wählen Sie ein bereits bei Claude Code angemeldetes Profil. Die Nutzung stammt aus den Sitzungen dieses Profils; Claude Code prüft die Kontolimits. Diese Auswahl ändert das Konto in anderen Apps nicht.",
            invalidFolder: "Wählen Sie einen vorhandenen Claude-Code-Profilordner, der Ihnen gehört und eine eigene .claude.json enthält. Andere dürfen nicht in den Ordner schreiben können, und die Datei darf keine Verknüpfung sein.",
            unknownAccount: "In diesem Profil wurde kein Konto erkannt.", noLimits: "Claude Code hat die Limits dieses Kontos noch nicht abgerufen.",
            signInHelp: "Bei einem anderen Claude-Konto anmelden")
        case .fr: return ClaudeAccountStrings(
            title: "Compte Claude", defaultAccount: "Compte par défaut", chooseFolder: "Choisir le dossier du compte…",
            explanation: "Choisissez un profil déjà connecté à Claude Code. L’usage provient des sessions de ce profil et Claude Code vérifie les limites de son compte. Ce choix ne change pas le compte dans les autres applications.",
            invalidFolder: "Choisissez un dossier de profil Claude Code existant qui vous appartient et contient son propre fichier .claude.json. Les autres utilisateurs ne doivent pas pouvoir écrire dans ce dossier et le fichier ne doit pas être un lien.",
            unknownAccount: "Aucun compte identifié dans ce profil.", noLimits: "Claude Code n’a pas encore renvoyé les limites de ce compte.",
            signInHelp: "Comment se connecter à un autre compte Claude")
        case .it: return ClaudeAccountStrings(
            title: "Account Claude", defaultAccount: "Account predefinito", chooseFolder: "Scegli la cartella dell’account…",
            explanation: "Scelga un profilo già connesso a Claude Code. L’utilizzo proviene dalle sessioni di quel profilo e Claude Code controlla i limiti dell’account. La scelta non cambia l’account nelle altre applicazioni.",
            invalidFolder: "Scelga una cartella di profilo Claude Code esistente di sua proprietà, con il proprio file .claude.json. Gli altri utenti non devono poter scrivere nella cartella e il file non deve essere un collegamento.",
            unknownAccount: "Nessun account identificato in questo profilo.", noLimits: "Claude Code non ha ancora restituito i limiti di questo account.",
            signInHelp: "Come accedere a un altro account Claude")
        case .ja: return ClaudeAccountStrings(
            title: "Claudeアカウント", defaultAccount: "デフォルトのアカウント", chooseFolder: "アカウントのフォルダを選択…",
            explanation: "Claude Codeにログイン済みのプロファイルを選択してください。使用量はそのプロファイルのセッションから読み取り、Claude Codeがアカウントの上限を確認します。他のアプリのアカウントは変更されません。",
            invalidFolder: "ご自身が所有し、独自の.claude.jsonファイルを含む既存のClaude Codeプロファイルフォルダを選択してください。他のユーザーが書き込めるフォルダや、リンクされたファイルは使用できません。",
            unknownAccount: "このプロファイルのアカウントを確認できません。", noLimits: "Claude Codeはまだこのアカウントの上限を返していません。",
            signInHelp: "別のClaudeアカウントにログインする方法")
        case .ko: return ClaudeAccountStrings(
            title: "Claude 계정", defaultAccount: "기본 계정", chooseFolder: "계정 폴더 선택…",
            explanation: "Claude Code에 이미 로그인한 프로필을 선택하세요. 사용량은 해당 프로필의 세션에서 읽고, Claude Code가 계정의 한도를 확인합니다. 다른 앱의 계정은 변경되지 않습니다.",
            invalidFolder: "본인 소유이며 자체 .claude.json 파일이 있는 기존 Claude Code 프로필 폴더를 선택하세요. 다른 사용자가 폴더에 쓸 수 없어야 하며 파일은 링크가 아니어야 합니다.",
            unknownAccount: "이 프로필에서 계정을 확인할 수 없습니다.", noLimits: "Claude Code가 아직 이 계정의 한도를 반환하지 않았습니다.",
            signInHelp: "다른 Claude 계정에 로그인하는 방법")
        case .uk: return ClaudeAccountStrings(
            title: "Обліковий запис Claude", defaultAccount: "Типовий обліковий запис", chooseFolder: "Вибрати папку облікового запису…",
            explanation: "Виберіть профіль, у якому вже виконано вхід до Claude Code. Використання береться із сеансів цього профілю, а Claude Code перевіряє ліміти облікового запису. Вибір не змінює обліковий запис в інших програмах.",
            invalidFolder: "Виберіть наявну папку профілю Claude Code, яка належить вам і містить власний файл .claude.json. Інші користувачі не повинні мати права запису в папку, а файл не повинен бути посиланням.",
            unknownAccount: "У цьому профілі обліковий запис не визначено.", noLimits: "Claude Code ще не повернув ліміти цього облікового запису.",
            signInHelp: "Як увійти до іншого облікового запису Claude")
        case .zhHans: return ClaudeAccountStrings(
            title: "Claude 账户", defaultAccount: "默认账户", chooseFolder: "选择账户文件夹…",
            explanation: "选择已登录 Claude Code 的配置。用量来自该配置的会话，Claude Code 会查询该账户的限额。此选择不会更改其他应用中的账户。",
            invalidFolder: "请选择属于您且包含独立 .claude.json 文件的现有 Claude Code 配置文件夹。其他用户不能具有该文件夹的写入权限，且该文件不能是链接。",
            unknownAccount: "未能识别此配置中的账户。", noLimits: "Claude Code 尚未返回此账户的限额。",
            signInHelp: "如何登录另一个 Claude 账户")
        case .zhTW: return ClaudeAccountStrings(
            title: "Claude 帳號", defaultAccount: "預設帳號", chooseFolder: "選擇帳號資料夾…",
            explanation: "選擇已登入 Claude Code 的設定檔。用量來自該設定檔的工作階段，Claude Code 會查詢該帳號的額度。此選擇不會變更其他應用程式中的帳號。",
            invalidFolder: "請選擇屬於您且包含獨立 .claude.json 檔案的現有 Claude Code 設定檔資料夾。其他使用者不可具有該資料夾的寫入權限，且該檔案不可為連結。",
            unknownAccount: "無法識別此設定檔中的帳號。", noLimits: "Claude Code 尚未傳回此帳號的額度。",
            signInHelp: "如何登入另一個 Claude 帳號")
        case .zhHK: return ClaudeAccountStrings(
            title: "Claude 帳戶", defaultAccount: "預設帳戶", chooseFolder: "選擇帳戶資料夾…",
            explanation: "選擇已登入 Claude Code 的設定檔。用量來自該設定檔的工作階段，Claude Code 會查詢該帳戶的限額。此選擇不會更改其他應用程式的帳戶。",
            invalidFolder: "請選擇屬於您且包含獨立 .claude.json 檔案的現有 Claude Code 設定檔資料夾。其他使用者不可擁有該資料夾的寫入權限，檔案亦不可是連結。",
            unknownAccount: "未能識別此設定檔中的帳戶。", noLimits: "Claude Code 尚未傳回此帳戶的限額。",
            signInHelp: "如何登入另一個 Claude 帳戶")
        }
    }
}
