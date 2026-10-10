// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

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
    let defaultAccount: String
    let refreshHint: String
    let cancelled: String
    let signIn: String
    let update: String
    let failed: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(title: "Codex accounts",
                explanation: "Each account gets its own limits card. Codex checks the selected CODEX_HOME folders every five minutes while the AI page is open. No model prompts are sent.",
                accountName: "Account name", remove: "Remove this account’s card", find: "Find local accounts", add: "Add folder…", check: "Check limits",
                fallback: "With no accounts selected, limits come from local Codex sessions.",
                resetsNote: "The banked resets card still belongs to the default Codex account, not the selected profiles.",
                chooseFolder: "Choose a Codex profile folder",
                invalidFolder: "Choose a separate CODEX_HOME containing config.toml or auth.json. You must own the folder and others must not be able to write to it. auth.json must be private and not linked. Codex may refresh its own credentials and caches; sign-in settings are not changed.",
                defaultAccount: "Default account", refreshHint: "Refresh to check this account’s limits.", cancelled: "Check cancelled.",
                signIn: "Sign in with ChatGPT in this Codex profile.", update: "Update Codex to check limits.", failed: "Could not check limits. Try again.")
        case .ru:
            return Self(title: "Аккаунты Codex",
                explanation: "Каждый аккаунт получает отдельную карточку лимитов. Codex проверяет выбранные папки CODEX_HOME раз в пять минут, пока раздел AI открыт. Запросы к моделям не отправляются.",
                accountName: "Название аккаунта", remove: "Убрать карточку аккаунта", find: "Найти локальные аккаунты", add: "Добавить папку…", check: "Проверить лимиты",
                fallback: "Без выбранных профилей лимиты берутся из локальных сессий Codex.",
                resetsNote: "Карточка резервных сбросов по-прежнему относится к аккаунту Codex по умолчанию, а не к выбранным профилям.",
                chooseFolder: "Выбери папку профиля Codex",
                invalidFolder: "Нужна отдельная папка CODEX_HOME с config.toml или auth.json. Папка должна принадлежать тебе и быть защищена от записи другими пользователями; auth.json — доступен только тебе, без ссылок. Codex может обновлять свои токены и кэш; настройки входа не изменяются.",
                defaultAccount: "Аккаунт по умолчанию", refreshHint: "Обнови, чтобы проверить лимиты аккаунта.", cancelled: "Проверка отменена.",
                signIn: "Войди в ChatGPT в этом профиле Codex.", update: "Обнови Codex для проверки лимитов.", failed: "Не удалось проверить лимиты. Попробуй ещё раз.")
        case .uk:
            return Self(title: "Облікові записи Codex",
                explanation: "Кожен обліковий запис має окрему картку лімітів. Codex перевіряє вибрані папки CODEX_HOME кожні п’ять хвилин, поки сторінка AI відкрита. Запити до моделей не надсилаються.",
                accountName: "Назва облікового запису", remove: "Прибрати картку облікового запису", find: "Знайти локальні записи", add: "Додати папку…", check: "Перевірити ліміти",
                fallback: "Без вибраних профілів ліміти беруться з локальних сеансів Codex.",
                resetsNote: "Картка резервних скидань належить типовому обліковому запису Codex, а не вибраним профілям.",
                chooseFolder: "Вибери папку профілю Codex",
                invalidFolder: "Потрібна окрема папка CODEX_HOME з config.toml або auth.json. Ти маєш бути її власником, без права запису для інших; auth.json має бути приватним, без посилань. Codex може оновлювати свої токени й кеш; налаштування входу не змінюються.",
                defaultAccount: "Типовий обліковий запис", refreshHint: "Онови, щоб перевірити ліміти запису.", cancelled: "Перевірку скасовано.",
                signIn: "Увійди в ChatGPT у цьому профілі Codex.", update: "Онови Codex для перевірки лімітів.", failed: "Не вдалося перевірити ліміти. Спробуй ще раз.")
        case .ptBR:
            return Self(title: "Contas do Codex",
                explanation: "Cada conta tem seu próprio cartão de limites. O Codex verifica as pastas CODEX_HOME selecionadas a cada cinco minutos enquanto a página de IA está aberta. Nenhum prompt é enviado aos modelos.",
                accountName: "Nome da conta", remove: "Remover o cartão desta conta", find: "Buscar contas locais", add: "Adicionar pasta…", check: "Verificar limites",
                fallback: "Sem contas selecionadas, os limites vêm das sessões locais do Codex.",
                resetsNote: "O cartão de redefinições reservadas continua vinculado à conta padrão do Codex, não aos perfis selecionados.",
                chooseFolder: "Escolha uma pasta de perfil do Codex",
                invalidFolder: "Escolha uma CODEX_HOME separada com config.toml ou auth.json. A pasta deve pertencer a você, sem permissão de escrita para outros. auth.json deve ser privado e sem links. O Codex pode atualizar credenciais e caches; as configurações de login não mudam.",
                defaultAccount: "Conta padrão", refreshHint: "Atualize para verificar os limites desta conta.", cancelled: "Verificação cancelada.",
                signIn: "Entre com o ChatGPT neste perfil do Codex.", update: "Atualize o Codex para verificar limites.", failed: "Não foi possível verificar os limites. Tente novamente.")
        case .tr:
            return Self(title: "Codex hesapları",
                explanation: "Her hesabın ayrı bir limit kartı vardır. AI sayfası açıkken Codex seçili CODEX_HOME klasörlerini beş dakikada bir kontrol eder. Modellere istem gönderilmez.",
                accountName: "Hesap adı", remove: "Bu hesabın kartını kaldır", find: "Yerel hesapları bul", add: "Klasör ekle…", check: "Limitleri kontrol et",
                fallback: "Hesap seçilmezse limitler yerel Codex oturumlarından alınır.",
                resetsNote: "Biriktirilmiş sıfırlamalar kartı seçili profillere değil, varsayılan Codex hesabına aittir.",
                chooseFolder: "Bir Codex profil klasörü seç",
                invalidFolder: "config.toml veya auth.json içeren ayrı bir CODEX_HOME seç. Klasör sana ait olmalı ve başkaları yazamamalıdır. auth.json özel ve bağlantısız olmalıdır. Codex kendi kimlik bilgilerini ve önbelleğini yenileyebilir; giriş ayarları değişmez.",
                defaultAccount: "Varsayılan hesap", refreshHint: "Bu hesabın limitlerini kontrol etmek için yenile.", cancelled: "Kontrol iptal edildi.",
                signIn: "Bu Codex profilinde ChatGPT ile giriş yap.", update: "Limitleri kontrol etmek için Codex’i güncelle.", failed: "Limitler kontrol edilemedi. Tekrar dene.")
        case .es:
            return Self(title: "Cuentas de Codex",
                explanation: "Cada cuenta tiene su propia tarjeta de límites. Codex consulta las carpetas CODEX_HOME seleccionadas cada cinco minutos mientras la página de IA está abierta. No se envían instrucciones a los modelos.",
                accountName: "Nombre de la cuenta", remove: "Quitar la tarjeta de esta cuenta", find: "Buscar cuentas locales", add: "Añadir carpeta…", check: "Consultar límites",
                fallback: "Sin cuentas seleccionadas, los límites proceden de las sesiones locales de Codex.",
                resetsNote: "La tarjeta de restablecimientos guardados sigue vinculada a la cuenta predeterminada de Codex, no a los perfiles seleccionados.",
                chooseFolder: "Elige una carpeta de perfil de Codex",
                invalidFolder: "Elige una CODEX_HOME independiente con config.toml o auth.json. Debes ser dueño de la carpeta y nadie más debe poder escribir en ella. auth.json debe ser privado y no estar enlazado. Codex puede renovar sus credenciales y cachés; no se cambia la configuración de inicio de sesión.",
                defaultAccount: "Cuenta predeterminada", refreshHint: "Actualiza para consultar los límites de esta cuenta.", cancelled: "Consulta cancelada.",
                signIn: "Inicia sesión con ChatGPT en este perfil de Codex.", update: "Actualiza Codex para consultar los límites.", failed: "No se pudieron consultar los límites. Inténtalo de nuevo.")
        case .sk:
            return Self(title: "Účty Codex",
                explanation: "Každý účet má vlastnú kartu limitov. Codex kontroluje vybrané priečinky CODEX_HOME každých päť minút, kým je stránka AI otvorená. Modelom sa neposielajú žiadne zadania.",
                accountName: "Názov účtu", remove: "Odstrániť kartu účtu", find: "Nájsť miestne účty", add: "Pridať priečinok…", check: "Skontrolovať limity",
                fallback: "Ak nie sú vybrané účty, limity pochádzajú z miestnych relácií Codex.",
                resetsNote: "Karta uložených obnovení stále patrí predvolenému účtu Codex, nie vybraným profilom.",
                chooseFolder: "Vyber priečinok profilu Codex",
                invalidFolder: "Vyber samostatný CODEX_HOME s config.toml alebo auth.json. Priečinok musí patriť tebe a ostatní doň nesmú zapisovať. auth.json musí byť súkromný a bez odkazov. Codex môže obnovovať svoje prihlasovacie údaje a vyrovnávaciu pamäť; nastavenia prihlásenia sa nemenia.",
                defaultAccount: "Predvolený účet", refreshHint: "Obnov zobrazenie a skontroluj limity účtu.", cancelled: "Kontrola zrušená.",
                signIn: "Prihlás sa cez ChatGPT v tomto profile Codex.", update: "Aktualizuj Codex na kontrolu limitov.", failed: "Limity sa nepodarilo skontrolovať. Skús to znova.")
        case .de:
            return Self(title: "Codex-Konten",
                explanation: "Jedes Konto erhält eine eigene Limitkarte. Codex prüft die gewählten CODEX_HOME-Ordner alle fünf Minuten, solange die KI-Seite geöffnet ist. Es werden keine Modellanfragen gesendet.",
                accountName: "Kontoname", remove: "Karte dieses Kontos entfernen", find: "Lokale Konten suchen", add: "Ordner hinzufügen…", check: "Limits prüfen",
                fallback: "Ohne ausgewählte Konten stammen die Limits aus lokalen Codex-Sitzungen.",
                resetsNote: "Die Karte für gespeicherte Zurücksetzungen gehört weiterhin zum Codex-Standardkonto, nicht zu den ausgewählten Profilen.",
                chooseFolder: "Codex-Profilordner auswählen",
                invalidFolder: "Wähle einen separaten CODEX_HOME-Ordner mit config.toml oder auth.json. Er muss dir gehören; andere dürfen nicht darin schreiben. auth.json muss privat und unverknüpft sein. Codex kann eigene Anmeldedaten und Caches erneuern; die Anmeldeeinstellungen bleiben unverändert.",
                defaultAccount: "Standardkonto", refreshHint: "Aktualisieren, um die Limits dieses Kontos zu prüfen.", cancelled: "Prüfung abgebrochen.",
                signIn: "Melde dich in diesem Codex-Profil mit ChatGPT an.", update: "Aktualisiere Codex, um Limits zu prüfen.", failed: "Limits konnten nicht geprüft werden. Versuche es erneut.")
        case .fr:
            return Self(title: "Comptes Codex",
                explanation: "Chaque compte dispose de sa propre carte de limites. Codex consulte les dossiers CODEX_HOME choisis toutes les cinq minutes tant que la page IA est ouverte. Aucune requête n’est envoyée aux modèles.",
                accountName: "Nom du compte", remove: "Retirer la carte de ce compte", find: "Chercher les comptes locaux", add: "Ajouter un dossier…", check: "Vérifier les limites",
                fallback: "Sans compte sélectionné, les limites proviennent des sessions locales de Codex.",
                resetsNote: "La carte des réinitialisations en réserve reste liée au compte Codex par défaut, pas aux profils sélectionnés.",
                chooseFolder: "Choisir un dossier de profil Codex",
                invalidFolder: "Choisis un CODEX_HOME distinct contenant config.toml ou auth.json. Le dossier doit t’appartenir et les autres ne doivent pas pouvoir y écrire. auth.json doit être privé et sans lien. Codex peut renouveler ses identifiants et caches ; les réglages de connexion restent inchangés.",
                defaultAccount: "Compte par défaut", refreshHint: "Actualise pour vérifier les limites de ce compte.", cancelled: "Vérification annulée.",
                signIn: "Connecte-toi avec ChatGPT dans ce profil Codex.", update: "Mets Codex à jour pour vérifier les limites.", failed: "Impossible de vérifier les limites. Réessaie.")
        case .it:
            return Self(title: "Account Codex",
                explanation: "Ogni account ha la propria scheda dei limiti. Codex controlla le cartelle CODEX_HOME selezionate ogni cinque minuti mentre la pagina IA è aperta. Non vengono inviati prompt ai modelli.",
                accountName: "Nome account", remove: "Rimuovi la scheda di questo account", find: "Trova account locali", add: "Aggiungi cartella…", check: "Controlla limiti",
                fallback: "Senza account selezionati, i limiti provengono dalle sessioni locali di Codex.",
                resetsNote: "La scheda dei ripristini accumulati resta associata all’account Codex predefinito, non ai profili selezionati.",
                chooseFolder: "Scegli una cartella di profilo Codex",
                invalidFolder: "Scegli una CODEX_HOME separata con config.toml o auth.json. Devi possedere la cartella e gli altri non devono potervi scrivere. auth.json deve essere privato e senza collegamenti. Codex può rinnovare credenziali e cache; le impostazioni di accesso non cambiano.",
                defaultAccount: "Account predefinito", refreshHint: "Aggiorna per controllare i limiti di questo account.", cancelled: "Controllo annullato.",
                signIn: "Accedi con ChatGPT in questo profilo Codex.", update: "Aggiorna Codex per controllare i limiti.", failed: "Impossibile controllare i limiti. Riprova.")
        case .ja:
            return Self(title: "Codex アカウント",
                explanation: "各アカウントに個別の上限カードを表示します。AI ページを開いている間、選択した CODEX_HOME フォルダを Codex が5分ごとに確認します。モデルへのプロンプトは送信しません。",
                accountName: "アカウント名", remove: "このアカウントのカードを削除", find: "ローカルアカウントを検索", add: "フォルダを追加…", check: "上限を確認",
                fallback: "アカウントを選択しない場合、ローカルの Codex セッションから上限を取得します。",
                resetsNote: "保存済みリセットのカードは、選択したプロファイルではなく、既定の Codex アカウントに適用されます。",
                chooseFolder: "Codex プロファイルフォルダを選択",
                invalidFolder: "config.toml または auth.json を含む独立した CODEX_HOME を選んでください。フォルダは自分が所有し、他のユーザーが書き込めない必要があります。auth.json は非公開で、リンクではないことが必要です。Codex は認証情報やキャッシュを更新する場合がありますが、ログイン設定は変更しません。",
                defaultAccount: "既定のアカウント", refreshHint: "更新してこのアカウントの上限を確認します。", cancelled: "確認をキャンセルしました。",
                signIn: "この Codex プロファイルで ChatGPT にログインしてください。", update: "上限を確認するには Codex を更新してください。", failed: "上限を確認できませんでした。もう一度お試しください。")
        case .ko:
            return Self(title: "Codex 계정",
                explanation: "계정마다 별도의 한도 카드가 표시됩니다. AI 페이지가 열려 있는 동안 Codex가 선택한 CODEX_HOME 폴더를 5분마다 확인합니다. 모델에 프롬프트를 보내지 않습니다.",
                accountName: "계정 이름", remove: "이 계정의 카드 제거", find: "로컬 계정 찾기", add: "폴더 추가…", check: "한도 확인",
                fallback: "선택한 계정이 없으면 로컬 Codex 세션에서 한도를 가져옵니다.",
                resetsNote: "저장된 재설정 카드는 선택한 프로필이 아닌 기본 Codex 계정에 적용됩니다.",
                chooseFolder: "Codex 프로필 폴더 선택",
                invalidFolder: "config.toml 또는 auth.json이 있는 별도의 CODEX_HOME을 선택하세요. 본인 소유의 폴더여야 하며 다른 사용자가 쓸 수 없어야 합니다. auth.json은 비공개 파일이고 링크가 아니어야 합니다. Codex가 자체 인증 정보와 캐시를 갱신할 수 있지만 로그인 설정은 변경하지 않습니다.",
                defaultAccount: "기본 계정", refreshHint: "새로고침하여 이 계정의 한도를 확인하세요.", cancelled: "확인이 취소되었습니다.",
                signIn: "이 Codex 프로필에서 ChatGPT로 로그인하세요.", update: "한도를 확인하려면 Codex를 업데이트하세요.", failed: "한도를 확인하지 못했습니다. 다시 시도하세요.")
        case .zhHans:
            return Self(title: "Codex 账户",
                explanation: "每个账户都有独立的限额卡片。AI 页面打开时，Codex 每五分钟检查一次所选的 CODEX_HOME 文件夹。不会向模型发送提示词。",
                accountName: "账户名称", remove: "移除此账户的卡片", find: "查找本地账户", add: "添加文件夹…", check: "检查限额",
                fallback: "未选择账户时，限额来自本地 Codex 会话。",
                resetsNote: "储备重置卡片仍对应默认 Codex 账户，而非所选配置文件。",
                chooseFolder: "选择 Codex 配置文件夹",
                invalidFolder: "请选择包含 config.toml 或 auth.json 的独立 CODEX_HOME。文件夹必须归你所有且不允许其他用户写入。auth.json 必须为私有文件且不能是链接。Codex 可能刷新自身凭据和缓存，但不会更改登录设置。",
                defaultAccount: "默认账户", refreshHint: "刷新以检查此账户的限额。", cancelled: "检查已取消。",
                signIn: "请在此 Codex 配置中使用 ChatGPT 登录。", update: "请更新 Codex 以检查限额。", failed: "无法检查限额，请重试。")
        case .zhTW:
            return Self(title: "Codex 帳號",
                explanation: "每個帳號都有獨立的額度卡片。AI 頁面開啟時，Codex 每五分鐘檢查一次所選的 CODEX_HOME 資料夾。不會向模型傳送提示詞。",
                accountName: "帳號名稱", remove: "移除此帳號的卡片", find: "尋找本機帳號", add: "加入資料夾…", check: "檢查額度",
                fallback: "未選取帳號時，額度來自本機 Codex 工作階段。",
                resetsNote: "儲備重設卡片仍對應預設 Codex 帳號，而非所選設定檔。",
                chooseFolder: "選取 Codex 設定檔資料夾",
                invalidFolder: "請選取包含 config.toml 或 auth.json 的獨立 CODEX_HOME。資料夾必須由你擁有且不允許其他使用者寫入。auth.json 必須為私人檔案且不能是連結。Codex 可能更新自己的憑證和快取，但不會變更登入設定。",
                defaultAccount: "預設帳號", refreshHint: "重新整理以檢查此帳號的額度。", cancelled: "已取消檢查。",
                signIn: "請在此 Codex 設定檔中使用 ChatGPT 登入。", update: "請更新 Codex 以檢查額度。", failed: "無法檢查額度，請再試一次。")
        case .zhHK:
            return Self(title: "Codex 帳戶",
                explanation: "每個帳戶都有獨立的限額卡片。AI 頁面開啟時，Codex 每五分鐘檢查一次所選的 CODEX_HOME 資料夾。不會向模型傳送提示詞。",
                accountName: "帳戶名稱", remove: "移除此帳戶的卡片", find: "尋找本機帳戶", add: "加入資料夾…", check: "檢查限額",
                fallback: "未選擇帳戶時，限額來自本機 Codex 工作階段。",
                resetsNote: "儲備重設卡片仍對應預設 Codex 帳戶，而非所選設定檔。",
                chooseFolder: "選擇 Codex 設定檔資料夾",
                invalidFolder: "請選擇包含 config.toml 或 auth.json 的獨立 CODEX_HOME。資料夾必須由你擁有，且不允許其他使用者寫入。auth.json 必須是私人檔案，不能是連結。Codex 可能更新自己的憑證及快取，但不會更改登入設定。",
                defaultAccount: "預設帳戶", refreshHint: "重新整理以檢查此帳戶的限額。", cancelled: "已取消檢查。",
                signIn: "請在此 Codex 設定檔中使用 ChatGPT 登入。", update: "請更新 Codex 以檢查限額。", failed: "無法檢查限額，請再試一次。")
        }
    }
}
