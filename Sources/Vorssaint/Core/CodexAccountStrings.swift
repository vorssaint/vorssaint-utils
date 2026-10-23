// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Codex accounts the AI page gives limits cards of their own.
struct CodexAccountStrings {
    let title: String
    let explanation: String
    let accountName: String
    let remove: String
    let find: String
    let add: String
    let check: String
    let fallback: String
    let resetsNote: String
    let chooseFolder: String
    let invalidFolder: String
    /// On a card whose folder no longer passes the checks above.
    let folderProblem: String
    /// The name the usual `~/.codex` home gets.
    let defaultName: String
    let defaultAccount: String
    let refreshHint: String
    let signIn: String
    let update: String
    let failed: String
}

extension FeatureStrings {
    static func codexAccounts(_ language: AppLanguage) -> CodexAccountStrings {
        switch language {
        case .enUS: return CodexAccountStrings(
            title: "Codex accounts",
            explanation: "Each CODEX_HOME folder you add gets its own limits card. While the AI Agents page is open, Codex checks each one about every five minutes with that folder’s own sign-in. No prompt is sent.",
            accountName: "Account name",
            remove: "Remove this account’s card",
            find: "Find local accounts",
            add: "Add folder…",
            check: "Check limits",
            fallback: "With no accounts added, Codex limits come from its local sessions.",
            resetsNote: "The Resets card still belongs to the default Codex account.",
            chooseFolder: "Choose a Codex folder",
            invalidFolder: "Choose a separate CODEX_HOME folder with config.toml or auth.json in it. The folder must be yours and not writable by others, and auth.json must be private and not a link. Codex may refresh its own sign-in and caches there.",
            folderProblem: "Choose this account’s folder again in Settings.",
            defaultName: "Default",
            defaultAccount: "Default account",
            refreshHint: "Refresh to check this account’s limits.",
            signIn: "Sign in with ChatGPT in this Codex folder.",
            update: "Update Codex to check limits.",
            failed: "Could not check limits. Try again.")
        case .ptBR: return CodexAccountStrings(
            title: "Contas do Codex",
            explanation: "Cada pasta CODEX_HOME adicionada ganha o próprio cartão de limites. Enquanto a página Agentes de IA está aberta, o Codex verifica cada uma aproximadamente a cada cinco minutos, com o login dessa pasta. Nenhum prompt é enviado.",
            accountName: "Nome da conta",
            remove: "Remover o cartão desta conta",
            find: "Buscar contas locais",
            add: "Adicionar pasta…",
            check: "Verificar limites",
            fallback: "Sem contas adicionadas, os limites do Codex vêm das sessões locais.",
            resetsNote: "O cartão Redefinições continua sendo da conta padrão do Codex.",
            chooseFolder: "Escolha uma pasta do Codex",
            invalidFolder: "Escolha uma pasta CODEX_HOME separada com config.toml ou auth.json. A pasta deve ser sua, sem permissão de escrita para outros, e o auth.json deve ser privado e não pode ser um link. O Codex pode atualizar o próprio login e caches nela.",
            folderProblem: "Escolha de novo a pasta desta conta nos Ajustes.",
            defaultName: "Padrão",
            defaultAccount: "Conta padrão",
            refreshHint: "Atualize para verificar os limites desta conta.",
            signIn: "Entre com o ChatGPT nesta pasta do Codex.",
            update: "Atualize o Codex para verificar os limites.",
            failed: "Não foi possível verificar os limites. Tente de novo.")
        case .tr: return CodexAccountStrings(
            title: "Codex hesapları",
            explanation: "Eklediğiniz her CODEX_HOME klasörünün kendi sınır kartı olur. YZ Ajanları sayfası açıkken Codex her birini o klasörün kendi oturumuyla yaklaşık beş dakikada bir denetler. İstem gönderilmez.",
            accountName: "Hesap adı",
            remove: "Bu hesabın kartını kaldır",
            find: "Yerel hesapları bul",
            add: "Klasör ekle…",
            check: "Sınırları denetle",
            fallback: "Hesap eklenmediğinde Codex sınırları yerel oturumlarından gelir.",
            resetsNote: "Sıfırlamalar kartı hâlâ varsayılan Codex hesabına aittir.",
            chooseFolder: "Bir Codex klasörü seçin",
            invalidFolder: "İçinde config.toml veya auth.json bulunan ayrı bir CODEX_HOME klasörü seçin. Klasör size ait olmalı ve başkaları ona yazamamalı, auth.json da özel olmalı ve bağlantı olmamalıdır. Codex orada kendi oturumunu ve önbelleklerini yenileyebilir.",
            folderProblem: "Bu hesabın klasörünü Ayarlar’da yeniden seçin.",
            defaultName: "Varsayılan",
            defaultAccount: "Varsayılan hesap",
            refreshHint: "Bu hesabın sınırlarını denetlemek için yenileyin.",
            signIn: "Bu Codex klasöründe ChatGPT ile oturum açın.",
            update: "Sınırları denetlemek için Codex’i güncelleyin.",
            failed: "Sınırlar denetlenemedi. Yeniden deneyin.")
        case .ru: return CodexAccountStrings(
            title: "Аккаунты Codex",
            explanation: "У каждой добавленной папки CODEX_HOME своя карточка лимитов. Пока открыта страница «ИИ-агенты», Codex проверяет каждую примерно раз в пять минут, используя вход этой папки. Запросы к модели не отправляются.",
            accountName: "Название аккаунта",
            remove: "Убрать карточку этого аккаунта",
            find: "Найти локальные аккаунты",
            add: "Добавить папку…",
            check: "Проверить лимиты",
            fallback: "Без добавленных аккаунтов лимиты Codex берутся из его локальных сессий.",
            resetsNote: "Карточка «Сбросы» по-прежнему относится к аккаунту Codex по умолчанию.",
            chooseFolder: "Выберите папку Codex",
            invalidFolder: "Выберите отдельную папку CODEX_HOME с файлом config.toml или auth.json. Папка должна принадлежать вам и быть защищена от записи другими, а auth.json должен быть закрытым и не быть ссылкой. Codex может обновлять в ней свой вход и кэш.",
            folderProblem: "Выберите папку этого аккаунта заново в настройках.",
            defaultName: "По умолчанию",
            defaultAccount: "Аккаунт по умолчанию",
            refreshHint: "Обновите, чтобы проверить лимиты этого аккаунта.",
            signIn: "Войдите через ChatGPT в этой папке Codex.",
            update: "Обновите Codex, чтобы проверять лимиты.",
            failed: "Не удалось проверить лимиты. Попробуйте ещё раз.")
        case .es: return CodexAccountStrings(
            title: "Cuentas de Codex",
            explanation: "Cada carpeta CODEX_HOME que añadas tiene su propia tarjeta de límites. Mientras la página Agentes de IA está abierta, Codex consulta cada una aproximadamente cada cinco minutos, con el inicio de sesión de esa carpeta. No se envía ninguna instrucción.",
            accountName: "Nombre de la cuenta",
            remove: "Quitar la tarjeta de esta cuenta",
            find: "Buscar cuentas locales",
            add: "Añadir carpeta…",
            check: "Consultar límites",
            fallback: "Sin cuentas añadidas, los límites de Codex proceden de sus sesiones locales.",
            resetsNote: "La tarjeta Reinicios sigue siendo de la cuenta predeterminada de Codex.",
            chooseFolder: "Elige una carpeta de Codex",
            invalidFolder: "Elige una carpeta CODEX_HOME independiente con config.toml o auth.json. La carpeta debe ser tuya y nadie más debe poder escribir en ella, y auth.json debe ser privado y no un enlace. Codex puede renovar ahí su propio inicio de sesión y sus cachés.",
            folderProblem: "Vuelve a elegir la carpeta de esta cuenta en Ajustes.",
            defaultName: "Predeterminada",
            defaultAccount: "Cuenta predeterminada",
            refreshHint: "Actualiza para consultar los límites de esta cuenta.",
            signIn: "Inicia sesión con ChatGPT en esta carpeta de Codex.",
            update: "Actualiza Codex para consultar los límites.",
            failed: "No se pudieron consultar los límites. Inténtalo de nuevo.")
        case .sk: return CodexAccountStrings(
            title: "Účty Codex",
            explanation: "Každý pridaný priečinok CODEX_HOME má vlastnú kartu limitov. Kým je otvorená stránka AI agenti, Codex kontroluje každý z nich približne raz za päť minút s prihlásením daného priečinka. Neposiela sa žiadny prompt.",
            accountName: "Názov účtu",
            remove: "Odstrániť kartu tohto účtu",
            find: "Nájsť miestne účty",
            add: "Pridať priečinok…",
            check: "Skontrolovať limity",
            fallback: "Bez pridaných účtov pochádzajú limity Codexu z jeho miestnych relácií.",
            resetsNote: "Karta Obnovenia stále patrí predvolenému účtu Codex.",
            chooseFolder: "Vyberte priečinok Codexu",
            invalidFolder: "Vyberte samostatný priečinok CODEX_HOME so súborom config.toml alebo auth.json. Priečinok musí patriť vám a ostatní doň nesmú zapisovať. Súbor auth.json musí byť súkromný a nesmie byť odkazom. Codex v ňom môže obnovovať svoje prihlásenie a vyrovnávacie pamäte.",
            folderProblem: "Vyberte priečinok tohto účtu znova v Nastaveniach.",
            defaultName: "Predvolený",
            defaultAccount: "Predvolený účet",
            refreshHint: "Obnovte a skontrolujte limity tohto účtu.",
            signIn: "Prihláste sa cez ChatGPT v tomto priečinku Codexu.",
            update: "Aktualizujte Codex, aby bolo možné skontrolovať limity.",
            failed: "Limity sa nepodarilo skontrolovať. Skúste to znova.")
        case .cs: return CodexAccountStrings(
            title: "Účty Codex",
            explanation: "Každá přidaná složka CODEX_HOME má vlastní kartu limitů. Dokud je otevřená stránka AI agenti, Codex kontroluje každou z nich přibližně jednou za pět minut s přihlášením dané složky. Neposílá se žádný prompt.",
            accountName: "Název účtu",
            remove: "Odstranit kartu tohoto účtu",
            find: "Najít místní účty",
            add: "Přidat složku…",
            check: "Zkontrolovat limity",
            fallback: "Bez přidaných účtů pocházejí limity Codexu z jeho místních relací.",
            resetsNote: "Karta Obnovení stále patří výchozímu účtu Codex.",
            chooseFolder: "Vyberte složku Codexu",
            invalidFolder: "Vyberte samostatnou složku CODEX_HOME se souborem config.toml nebo auth.json. Složka musí patřit vám a ostatní do ní nesmí zapisovat. Soubor auth.json musí být soukromý a nesmí být odkazem. Codex v ní může obnovovat své přihlášení a mezipaměti.",
            folderProblem: "Vyberte složku tohoto účtu znovu v Nastavení.",
            defaultName: "Výchozí",
            defaultAccount: "Výchozí účet",
            refreshHint: "Obnovte a zkontrolujte limity tohoto účtu.",
            signIn: "Přihlaste se přes ChatGPT v této složce Codexu.",
            update: "Aktualizujte Codex, aby bylo možné zkontrolovat limity.",
            failed: "Limity se nepodařilo zkontrolovat. Zkuste to znovu.")
        case .de: return CodexAccountStrings(
            title: "Codex-Konten",
            explanation: "Jeder hinzugefügte CODEX_HOME-Ordner erhält eine eigene Limitkarte. Solange die Seite KI-Agenten geöffnet ist, prüft Codex jeden etwa alle fünf Minuten mit der Anmeldung dieses Ordners. Es wird kein Prompt gesendet.",
            accountName: "Kontoname",
            remove: "Karte dieses Kontos entfernen",
            find: "Lokale Konten suchen",
            add: "Ordner hinzufügen…",
            check: "Limits prüfen",
            fallback: "Ohne hinzugefügte Konten stammen die Codex-Limits aus seinen lokalen Sitzungen.",
            resetsNote: "Die Karte Zurücksetzungen gehört weiterhin zum Codex-Standardkonto.",
            chooseFolder: "Codex-Ordner wählen",
            invalidFolder: "Wähle einen separaten CODEX_HOME-Ordner mit config.toml oder auth.json. Der Ordner muss dir gehören und darf für andere nicht beschreibbar sein, und auth.json muss privat und kein Link sein. Codex kann dort seine eigene Anmeldung und Caches erneuern.",
            folderProblem: "Wähle den Ordner dieses Kontos in den Einstellungen erneut.",
            defaultName: "Standard",
            defaultAccount: "Standardkonto",
            refreshHint: "Aktualisiere, um die Limits dieses Kontos zu prüfen.",
            signIn: "Melde dich in diesem Codex-Ordner mit ChatGPT an.",
            update: "Aktualisiere Codex, um die Limits zu prüfen.",
            failed: "Limits konnten nicht geprüft werden. Versuche es erneut.")
        case .fr: return CodexAccountStrings(
            title: "Comptes Codex",
            explanation: "Chaque dossier CODEX_HOME ajouté a sa propre carte de limites. Tant que la page Agents IA est ouverte, Codex vérifie chacun environ toutes les cinq minutes, avec la connexion de ce dossier. Aucune requête n’est envoyée.",
            accountName: "Nom du compte",
            remove: "Retirer la carte de ce compte",
            find: "Chercher les comptes locaux",
            add: "Ajouter un dossier…",
            check: "Vérifier les limites",
            fallback: "Sans compte ajouté, les limites de Codex proviennent de ses sessions locales.",
            resetsNote: "La carte Réinitialisations reste celle du compte Codex par défaut.",
            chooseFolder: "Choisissez un dossier Codex",
            invalidFolder: "Choisissez un dossier CODEX_HOME distinct contenant config.toml ou auth.json. Le dossier doit vous appartenir et ne pas être modifiable par d’autres, et auth.json doit être privé et ne pas être un lien. Codex peut y renouveler sa propre connexion et ses caches.",
            folderProblem: "Choisissez à nouveau le dossier de ce compte dans les Réglages.",
            defaultName: "Par défaut",
            defaultAccount: "Compte par défaut",
            refreshHint: "Actualisez pour vérifier les limites de ce compte.",
            signIn: "Connectez-vous avec ChatGPT dans ce dossier Codex.",
            update: "Mettez Codex à jour pour vérifier les limites.",
            failed: "Impossible de vérifier les limites. Réessayez.")
        case .it: return CodexAccountStrings(
            title: "Account Codex",
            explanation: "Ogni cartella CODEX_HOME aggiunta ha la propria scheda dei limiti. Mentre la pagina Agenti IA è aperta, Codex controlla ciascuna circa ogni cinque minuti, con l’accesso di quella cartella. Non viene inviato alcun prompt.",
            accountName: "Nome account",
            remove: "Rimuovi la scheda di questo account",
            find: "Trova account locali",
            add: "Aggiungi cartella…",
            check: "Controlla limiti",
            fallback: "Senza account aggiunti, i limiti di Codex provengono dalle sue sessioni locali.",
            resetsNote: "La scheda Ripristini resta dell’account Codex predefinito.",
            chooseFolder: "Scegli una cartella di Codex",
            invalidFolder: "Scegli una cartella CODEX_HOME separata con config.toml o auth.json. La cartella deve essere tua e gli altri non devono poterci scrivere, e auth.json deve essere privato e non un collegamento. Codex può rinnovare lì il proprio accesso e le cache.",
            folderProblem: "Scegli di nuovo la cartella di questo account nelle Impostazioni.",
            defaultName: "Predefinito",
            defaultAccount: "Account predefinito",
            refreshHint: "Aggiorna per controllare i limiti di questo account.",
            signIn: "Accedi con ChatGPT in questa cartella di Codex.",
            update: "Aggiorna Codex per controllare i limiti.",
            failed: "Impossibile controllare i limiti. Riprova.")
        case .ja: return CodexAccountStrings(
            title: "Codexアカウント",
            explanation: "追加したCODEX_HOMEフォルダごとに上限カードが表示されます。AIエージェントのページを開いている間、Codexがそのフォルダのサインインで各フォルダを約5分ごとに確認します。プロンプトは送信されません。",
            accountName: "アカウント名",
            remove: "このアカウントのカードを削除",
            find: "ローカルのアカウントを検索",
            add: "フォルダを追加…",
            check: "上限を確認",
            fallback: "アカウントを追加しない場合、Codexの上限はローカルのセッションから取得されます。",
            resetsNote: "リセットのカードは引き続き既定のCodexアカウントのものです。",
            chooseFolder: "Codexのフォルダを選択",
            invalidFolder: "config.tomlまたはauth.jsonを含む別のCODEX_HOMEフォルダを選択してください。フォルダは自分が所有し、他のユーザーが書き込めない必要があります。auth.jsonは非公開で、リンクではない必要があります。Codexはそこで自身のサインイン情報とキャッシュを更新することがあります。",
            folderProblem: "設定でこのアカウントのフォルダを選び直してください。",
            defaultName: "既定",
            defaultAccount: "既定のアカウント",
            refreshHint: "更新してこのアカウントの上限を確認します。",
            signIn: "このCodexフォルダでChatGPTにサインインしてください。",
            update: "上限を確認するにはCodexをアップデートしてください。",
            failed: "上限を確認できませんでした。もう一度お試しください。")
        case .ko: return CodexAccountStrings(
            title: "Codex 계정",
            explanation: "추가한 CODEX_HOME 폴더마다 한도 카드가 따로 표시됩니다. AI 에이전트 페이지가 열려 있는 동안 Codex가 각 폴더의 로그인으로 약 5분마다 확인합니다. 프롬프트는 보내지 않습니다.",
            accountName: "계정 이름",
            remove: "이 계정의 카드 제거",
            find: "로컬 계정 찾기",
            add: "폴더 추가…",
            check: "한도 확인",
            fallback: "추가한 계정이 없으면 Codex 한도는 로컬 세션에서 가져옵니다.",
            resetsNote: "초기화 카드는 계속 기본 Codex 계정에 해당합니다.",
            chooseFolder: "Codex 폴더 선택",
            invalidFolder: "config.toml 또는 auth.json이 있는 별도의 CODEX_HOME 폴더를 선택하세요. 폴더는 본인 소유여야 하고 다른 사용자가 쓸 수 없어야 하며, auth.json은 비공개 파일이고 링크가 아니어야 합니다. Codex가 그 폴더에서 자체 로그인 정보와 캐시를 갱신할 수 있습니다.",
            folderProblem: "설정에서 이 계정의 폴더를 다시 선택하세요.",
            defaultName: "기본",
            defaultAccount: "기본 계정",
            refreshHint: "새로고침하여 이 계정의 한도를 확인하세요.",
            signIn: "이 Codex 폴더에서 ChatGPT로 로그인하세요.",
            update: "한도를 확인하려면 Codex를 업데이트하세요.",
            failed: "한도를 확인하지 못했습니다. 다시 시도하세요.")
        case .uk: return CodexAccountStrings(
            title: "Облікові записи Codex",
            explanation: "Кожна додана папка CODEX_HOME має власну картку лімітів. Поки відкрита сторінка «ШІ-агенти», Codex перевіряє кожну приблизно раз на п’ять хвилин, використовуючи вхід цієї папки. Запити до моделі не надсилаються.",
            accountName: "Назва облікового запису",
            remove: "Прибрати картку цього облікового запису",
            find: "Знайти локальні облікові записи",
            add: "Додати папку…",
            check: "Перевірити ліміти",
            fallback: "Без доданих облікових записів ліміти Codex беруться з його локальних сеансів.",
            resetsNote: "Картка «Скидання» і далі належить типовому обліковому запису Codex.",
            chooseFolder: "Виберіть папку Codex",
            invalidFolder: "Виберіть окрему папку CODEX_HOME з файлом config.toml або auth.json. Папка має належати вам і бути захищеною від запису іншими, а auth.json має бути приватним і не бути посиланням. Codex може оновлювати в ній свій вхід і кеш.",
            folderProblem: "Виберіть папку цього облікового запису ще раз у налаштуваннях.",
            defaultName: "Типовий",
            defaultAccount: "Типовий обліковий запис",
            refreshHint: "Оновіть, щоб перевірити ліміти цього облікового запису.",
            signIn: "Увійдіть через ChatGPT у цій папці Codex.",
            update: "Оновіть Codex, щоб перевіряти ліміти.",
            failed: "Не вдалося перевірити ліміти. Спробуйте ще раз.")
        case .zhHans: return CodexAccountStrings(
            title: "Codex 账户",
            explanation: "每个添加的 CODEX_HOME 文件夹都有自己的额度卡片。AI 智能体页面打开时，Codex 会用该文件夹自己的登录信息检查它，大约每五分钟一次。不会发送提示。",
            accountName: "账户名称",
            remove: "移除此账户的卡片",
            find: "查找本地账户",
            add: "添加文件夹…",
            check: "检查额度",
            fallback: "未添加账户时，Codex 额度来自其本地会话。",
            resetsNote: "重置卡片仍属于默认 Codex 账户。",
            chooseFolder: "选择 Codex 文件夹",
            invalidFolder: "请选择包含 config.toml 或 auth.json 的独立 CODEX_HOME 文件夹。该文件夹必须归你所有，其他用户不能写入；auth.json 必须是私有文件，且不能是链接。Codex 可能会在其中刷新自己的登录信息和缓存。",
            folderProblem: "请在设置中重新选择此账户的文件夹。",
            defaultName: "默认",
            defaultAccount: "默认账户",
            refreshHint: "刷新以检查此账户的额度。",
            signIn: "请在此 Codex 文件夹中使用 ChatGPT 登录。",
            update: "请更新 Codex 以检查额度。",
            failed: "无法检查额度，请重试。")
        case .zhTW: return CodexAccountStrings(
            title: "Codex 帳號",
            explanation: "每個加入的 CODEX_HOME 資料夾都有自己的額度卡片。AI 代理頁面開啟時，Codex 會用該資料夾自己的登入資訊檢查它，大約每五分鐘一次。不會傳送提示。",
            accountName: "帳號名稱",
            remove: "移除此帳號的卡片",
            find: "尋找本機帳號",
            add: "加入資料夾…",
            check: "檢查額度",
            fallback: "未加入帳號時，Codex 額度來自其本機工作階段。",
            resetsNote: "重設卡片仍屬於預設 Codex 帳號。",
            chooseFolder: "選擇 Codex 資料夾",
            invalidFolder: "請選擇包含 config.toml 或 auth.json 的獨立 CODEX_HOME 資料夾。資料夾必須由你擁有，其他使用者不能寫入；auth.json 必須是私人檔案，且不能是連結。Codex 可能會在其中更新自己的登入資訊和快取。",
            folderProblem: "請在設定中重新選擇此帳號的資料夾。",
            defaultName: "預設",
            defaultAccount: "預設帳號",
            refreshHint: "重新整理以檢查此帳號的額度。",
            signIn: "請在此 Codex 資料夾中使用 ChatGPT 登入。",
            update: "請更新 Codex 以檢查額度。",
            failed: "無法檢查額度，請再試一次。")
        case .zhHK: return CodexAccountStrings(
            title: "Codex 帳戶",
            explanation: "每個加入的 CODEX_HOME 資料夾都有自己的額度卡片。AI 代理頁面開啟時，Codex 會用該資料夾自己的登入資料檢查它，大約每五分鐘一次。不會傳送提示。",
            accountName: "帳戶名稱",
            remove: "移除此帳戶的卡片",
            find: "尋找本機帳戶",
            add: "加入資料夾…",
            check: "檢查額度",
            fallback: "未加入帳戶時，Codex 額度來自其本機工作階段。",
            resetsNote: "重設卡片仍屬於預設 Codex 帳戶。",
            chooseFolder: "選擇 Codex 資料夾",
            invalidFolder: "請選擇包含 config.toml 或 auth.json 的獨立 CODEX_HOME 資料夾。資料夾必須由你擁有，其他使用者不能寫入；auth.json 必須是私人檔案，而且不能是連結。Codex 可能會在其中更新自己的登入資料及快取。",
            folderProblem: "請在設定中重新選擇此帳戶的資料夾。",
            defaultName: "預設",
            defaultAccount: "預設帳戶",
            refreshHint: "重新整理以檢查此帳戶的額度。",
            signIn: "請在此 Codex 資料夾中使用 ChatGPT 登入。",
            update: "請更新 Codex 以檢查額度。",
            failed: "無法檢查額度，請再試一次。")
        }
    }
}
