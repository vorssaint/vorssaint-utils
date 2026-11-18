// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The CLIProxyAPI hubs whose accounts the AI page gives limits cards.
struct AgentHubStrings {
    let title: String
    let explanation: String
    /// Said beside the key field: what the key can do and where it goes.
    let keyNote: String
    let add: String
    let address: String
    let key: String
    let name: String
    let save: String
    let invalidAddress: String
    let invalidKey: String
    let saveFailed: String
    /// Adding a fifth hub; a hub already added can still take a new key.
    let full: String
    let remove: String
    let check: String
    let notChecked: String
    let checking: String
    let connected: String
    let noAccounts: String
    let remoteDisabled: String
    let wrongKey: String
    let blocked: String
    let managementOff: String
    let insecure: String
    let unreachable: String
    /// A hub status other than the ones above; `%d` is the HTTP status.
    let failedFormat: String
    /// On a card whose account the provider refused through the hub.
    let accountSignIn: String
    /// On every card of a hub that refuses Vorssaint; Settings says why.
    let cardRefused: String
    let cardUnreachable: String
    let cardFailed: String

    /// A hub's row in Settings.
    func state(_ state: AgentHubState?) -> String {
        switch state {
        case nil: return notChecked
        case .checking?: return checking
        case .ready(let accounts)?: return accounts == 0 ? noAccounts : connected
        case .remoteDisabled?: return remoteDisabled
        case .wrongKey?: return wrongKey
        case .blocked?: return blocked
        case .managementOff?: return managementOff
        case .insecure?: return insecure
        case .unreachable?: return unreachable
        case .failed(let status)?: return status > 0 ? String(format: failedFormat, status) : cardFailed
        }
    }

    /// What a hub account's card says about its hub; nil while the hub answers.
    func cardProblem(_ state: AgentHubState) -> String? {
        switch state {
        case .checking, .ready: return nil
        case .unreachable: return cardUnreachable
        case .failed: return cardFailed
        case .remoteDisabled, .wrongKey, .blocked, .managementOff, .insecure: return cardRefused
        }
    }
}

extension FeatureStrings {
    static func agentHubs(_ language: AppLanguage) -> AgentHubStrings {
        switch language {
        case .enUS: return AgentHubStrings(
            title: "CLIProxyAPI hubs",
            explanation: "Add a CLIProxyAPI hub to give each Claude and Codex subscription it pools a limits card. While the AI Agents page is open, Vorssaint asks the hub about every five minutes, and the hub checks each account with that account’s own sign-in. No prompt is sent. An agent’s hub accounts take the place of its default limits card.",
            keyNote: "The management key also lets whoever holds it change the hub and download its sign-ins. Vorssaint keeps it in a private file on this Mac, leaves it out of settings exports and sends it only to the hub.",
            add: "Add hub…",
            address: "Address",
            key: "Management key",
            name: "Name (optional)",
            save: "Add",
            invalidAddress: "Enter the hub’s address, such as https://hub.example.net:8317.",
            invalidKey: "Enter the management key on one line.",
            saveFailed: "Could not save the hub. Try again.",
            full: "Up to four hubs fit. Remove one first, or enter an added hub’s address to replace its key.",
            remove: "Remove this hub",
            check: "Check hubs",
            notChecked: "Checked while the AI Agents page is open.",
            checking: "Checking…",
            connected: "Connected",
            noAccounts: "Connected. The hub pools no Claude or Codex subscription.",
            remoteDisabled: "The hub accepts management calls only from its own machine. Set remote-management.allow-remote to true in its config.",
            wrongKey: "The hub refused this key. Add the hub again with the right key. Until then Vorssaint stops asking, because the hub blocks a Mac after five wrong keys.",
            blocked: "The hub blocked this Mac after too many wrong keys. It accepts it again after half an hour.",
            managementOff: "The hub’s management API is off. Set remote-management.secret-key in its config.",
            insecure: "macOS allows plain http only to an IP address or a .local name. Use https or the hub’s IP address.",
            unreachable: "Could not reach the hub. Its accounts keep their last readings.",
            failedFormat: "The hub answered with HTTP %d.",
            accountSignIn: "The hub’s sign-in for this account was refused.",
            cardRefused: "The hub refused the check. See Settings.",
            cardUnreachable: "Could not reach the hub.",
            cardFailed: "The hub could not answer. Try again.")
        case .ptBR: return AgentHubStrings(
            title: "Hubs do CLIProxyAPI",
            explanation: "Adicione um hub do CLIProxyAPI para dar um cartão de limites a cada assinatura do Claude e do Codex que ele reúne. Enquanto a página Agentes de IA está aberta, o Vorssaint consulta o hub aproximadamente a cada cinco minutos, e o hub verifica cada conta com o login dela. Nenhum prompt é enviado. As contas do hub de um agente substituem o cartão de limites padrão dele.",
            keyNote: "A chave de gerenciamento também permite a quem a tem alterar o hub e baixar os logins dele. O Vorssaint a guarda em um arquivo privado neste Mac, a deixa fora das exportações de ajustes e a envia apenas ao hub.",
            add: "Adicionar hub…",
            address: "Endereço",
            key: "Chave de gerenciamento",
            name: "Nome (opcional)",
            save: "Adicionar",
            invalidAddress: "Digite o endereço do hub, como https://hub.example.net:8317.",
            invalidKey: "Digite a chave de gerenciamento em uma única linha.",
            saveFailed: "Não foi possível salvar o hub. Tente de novo.",
            full: "Cabem até quatro hubs. Remova um antes ou digite o endereço de um hub já adicionado para trocar a chave dele.",
            remove: "Remover este hub",
            check: "Verificar hubs",
            notChecked: "Verificado enquanto a página Agentes de IA está aberta.",
            checking: "Verificando…",
            connected: "Conectado",
            noAccounts: "Conectado. O hub não reúne nenhuma assinatura do Claude ou do Codex.",
            remoteDisabled: "O hub só aceita chamadas de gerenciamento da própria máquina. Defina remote-management.allow-remote como true na configuração dele.",
            wrongKey: "O hub recusou esta chave. Adicione o hub de novo com a chave certa. Até lá o Vorssaint para de consultar, porque o hub bloqueia um Mac após cinco chaves erradas.",
            blocked: "O hub bloqueou este Mac após chaves erradas demais. Ele volta a aceitá-lo depois de meia hora.",
            managementOff: "A API de gerenciamento do hub está desligada. Defina remote-management.secret-key na configuração dele.",
            insecure: "O macOS só permite http simples para um endereço IP ou um nome .local. Use https ou o endereço IP do hub.",
            unreachable: "Não foi possível acessar o hub. As contas dele mantêm as últimas leituras.",
            failedFormat: "O hub respondeu com HTTP %d.",
            accountSignIn: "O login do hub nesta conta foi recusado.",
            cardRefused: "O hub recusou a verificação. Veja os Ajustes.",
            cardUnreachable: "Não foi possível acessar o hub.",
            cardFailed: "O hub não conseguiu responder. Tente de novo.")
        case .tr: return AgentHubStrings(
            title: "CLIProxyAPI hub’ları",
            explanation: "Bir CLIProxyAPI hub’ı ekleyerek bir araya getirdiği her Claude ve Codex aboneliğine bir sınır kartı verin. YZ Ajanları sayfası açıkken Vorssaint hub’a yaklaşık beş dakikada bir sorar; hub da her hesabı o hesabın kendi oturumuyla denetler. İstem gönderilmez. Bir ajanın hub hesapları, onun varsayılan sınır kartının yerini alır.",
            keyNote: "Yönetim anahtarı, sahibine hub’ı değiştirme ve oturumlarını indirme olanağı da verir. Vorssaint onu bu Mac’te özel bir dosyada saklar, ayar dışa aktarımlarına koymaz ve yalnızca hub’a gönderir.",
            add: "Hub ekle…",
            address: "Adres",
            key: "Yönetim anahtarı",
            name: "Ad (isteğe bağlı)",
            save: "Ekle",
            invalidAddress: "Hub’ın adresini girin, örneğin https://hub.example.net:8317.",
            invalidKey: "Yönetim anahtarını tek satır olarak girin.",
            saveFailed: "Hub kaydedilemedi. Yeniden deneyin.",
            full: "En fazla dört hub eklenebilir. Önce birini kaldırın ya da anahtarını değiştirmek için eklenmiş bir hub’ın adresini girin.",
            remove: "Bu hub’ı kaldır",
            check: "Hub’ları denetle",
            notChecked: "YZ Ajanları sayfası açıkken denetlenir.",
            checking: "Denetleniyor…",
            connected: "Bağlı",
            noAccounts: "Bağlı. Hub hiçbir Claude veya Codex aboneliği barındırmıyor.",
            remoteDisabled: "Hub yönetim çağrılarını yalnızca kendi makinesinden kabul ediyor. Yapılandırmasında remote-management.allow-remote değerini true yapın.",
            wrongKey: "Hub bu anahtarı reddetti. Hub’ı doğru anahtarla yeniden ekleyin. O zamana kadar Vorssaint sormayı bırakır, çünkü hub beş yanlış anahtardan sonra bir Mac’i engeller.",
            blocked: "Hub, çok sayıda yanlış anahtardan sonra bu Mac’i engelledi. Yarım saat sonra yeniden kabul eder.",
            managementOff: "Hub’ın yönetim API’si kapalı. Yapılandırmasında remote-management.secret-key değerini ayarlayın.",
            insecure: "macOS düz http’ye yalnızca bir IP adresi veya .local adı için izin verir. https’yi ya da hub’ın IP adresini kullanın.",
            unreachable: "Hub’a ulaşılamadı. Hesapları son okumalarını korur.",
            failedFormat: "Hub HTTP %d ile yanıt verdi.",
            accountSignIn: "Hub’ın bu hesaptaki oturumu reddedildi.",
            cardRefused: "Hub denetimi reddetti. Ayarlar’a bakın.",
            cardUnreachable: "Hub’a ulaşılamadı.",
            cardFailed: "Hub yanıt veremedi. Yeniden deneyin.")
        case .ru: return AgentHubStrings(
            title: "Хабы CLIProxyAPI",
            explanation: "Добавьте хаб CLIProxyAPI, чтобы у каждой подписки Claude и Codex, которую он объединяет, была карточка лимитов. Пока открыта страница «ИИ-агенты», Vorssaint опрашивает хаб примерно раз в пять минут, а хаб проверяет каждый аккаунт с его собственным входом. Запросы к модели не отправляются. Аккаунты хаба заменяют стандартную карточку лимитов своего агента.",
            keyNote: "Ключ управления также позволяет его владельцу менять настройки хаба и скачивать его входы. Vorssaint хранит его в закрытом файле на этом Mac, не включает в экспорт настроек и отправляет только хабу.",
            add: "Добавить хаб…",
            address: "Адрес",
            key: "Ключ управления",
            name: "Название (необязательно)",
            save: "Добавить",
            invalidAddress: "Введите адрес хаба, например https://hub.example.net:8317.",
            invalidKey: "Введите ключ управления одной строкой.",
            saveFailed: "Не удалось сохранить хаб. Попробуйте ещё раз.",
            full: "Можно добавить не больше четырёх хабов. Сначала удалите один или введите адрес уже добавленного хаба, чтобы заменить его ключ.",
            remove: "Удалить этот хаб",
            check: "Проверить хабы",
            notChecked: "Проверяется, пока открыта страница «ИИ-агенты».",
            checking: "Проверка…",
            connected: "Подключено",
            noAccounts: "Подключено. Хаб не объединяет ни одной подписки Claude или Codex.",
            remoteDisabled: "Хаб принимает запросы управления только со своего компьютера. Задайте remote-management.allow-remote: true в его конфигурации.",
            wrongKey: "Хаб отклонил этот ключ. Добавьте хаб снова с правильным ключом. До тех пор Vorssaint не обращается к нему, потому что после пяти неверных ключей хаб блокирует Mac.",
            blocked: "Хаб заблокировал этот Mac после слишком многих неверных ключей. Через полчаса он снова его примет.",
            managementOff: "API управления хаба отключён. Задайте remote-management.secret-key в его конфигурации.",
            insecure: "macOS разрешает обычный http только для IP-адреса или имени .local. Используйте https или IP-адрес хаба.",
            unreachable: "Не удалось связаться с хабом. Его аккаунты сохраняют последние показания.",
            failedFormat: "Хаб ответил с кодом HTTP %d.",
            accountSignIn: "Вход хаба в этот аккаунт отклонён.",
            cardRefused: "Хаб отклонил проверку. Откройте настройки.",
            cardUnreachable: "Не удалось связаться с хабом.",
            cardFailed: "Хаб не смог ответить. Попробуйте ещё раз.")
        case .es: return AgentHubStrings(
            title: "Hubs de CLIProxyAPI",
            explanation: "Añade un hub de CLIProxyAPI para dar una tarjeta de límites a cada suscripción de Claude y Codex que agrupa. Mientras la página Agentes de IA está abierta, Vorssaint consulta el hub aproximadamente cada cinco minutos, y el hub comprueba cada cuenta con su propio inicio de sesión. No se envía ninguna instrucción. Las cuentas del hub de un agente sustituyen su tarjeta de límites predeterminada.",
            keyNote: "La clave de gestión también permite a quien la tenga cambiar el hub y descargar sus inicios de sesión. Vorssaint la guarda en un archivo privado en este Mac, la deja fuera de las exportaciones de ajustes y solo la envía al hub.",
            add: "Añadir hub…",
            address: "Dirección",
            key: "Clave de gestión",
            name: "Nombre (opcional)",
            save: "Añadir",
            invalidAddress: "Introduce la dirección del hub, como https://hub.example.net:8317.",
            invalidKey: "Introduce la clave de gestión en una sola línea.",
            saveFailed: "No se pudo guardar el hub. Inténtalo de nuevo.",
            full: "Caben hasta cuatro hubs. Quita uno primero o introduce la dirección de un hub ya añadido para cambiar su clave.",
            remove: "Quitar este hub",
            check: "Consultar hubs",
            notChecked: "Se consulta mientras la página Agentes de IA está abierta.",
            checking: "Consultando…",
            connected: "Conectado",
            noAccounts: "Conectado. El hub no agrupa ninguna suscripción de Claude ni de Codex.",
            remoteDisabled: "El hub solo acepta llamadas de gestión desde su propia máquina. Pon remote-management.allow-remote en true en su configuración.",
            wrongKey: "El hub rechazó esta clave. Vuelve a añadir el hub con la clave correcta. Hasta entonces Vorssaint deja de consultarlo, porque el hub bloquea un Mac tras cinco claves incorrectas.",
            blocked: "El hub bloqueó este Mac tras demasiadas claves incorrectas. Volverá a aceptarlo pasada media hora.",
            managementOff: "La API de gestión del hub está desactivada. Define remote-management.secret-key en su configuración.",
            insecure: "macOS solo permite http sin cifrar hacia una dirección IP o un nombre .local. Usa https o la dirección IP del hub.",
            unreachable: "No se pudo conectar con el hub. Sus cuentas conservan sus últimas lecturas.",
            failedFormat: "El hub respondió con HTTP %d.",
            accountSignIn: "Se rechazó el inicio de sesión del hub en esta cuenta.",
            cardRefused: "El hub rechazó la consulta. Revisa los Ajustes.",
            cardUnreachable: "No se pudo conectar con el hub.",
            cardFailed: "El hub no pudo responder. Inténtalo de nuevo.")
        case .sk: return AgentHubStrings(
            title: "Huby CLIProxyAPI",
            explanation: "Pridajte hub CLIProxyAPI a každé predplatné Claude a Codex, ktoré združuje, dostane kartu limitov. Kým je otvorená stránka AI agenti, Vorssaint sa hubu pýta približne raz za päť minút a hub kontroluje každý účet s jeho vlastným prihlásením. Neposiela sa žiadny prompt. Účty hubu nahradia predvolenú kartu limitov svojho agenta.",
            keyNote: "Kľúč na správu umožňuje jeho držiteľovi aj meniť hub a sťahovať jeho prihlásenia. Vorssaint ho uchováva v súkromnom súbore v tomto Macu, nezahŕňa ho do exportov nastavení a posiela ho iba hubu.",
            add: "Pridať hub…",
            address: "Adresa",
            key: "Kľúč na správu",
            name: "Názov (voliteľné)",
            save: "Pridať",
            invalidAddress: "Zadajte adresu hubu, napríklad https://hub.example.net:8317.",
            invalidKey: "Zadajte kľúč na správu na jednom riadku.",
            saveFailed: "Hub sa nepodarilo uložiť. Skúste to znova.",
            full: "Zmestia sa najviac štyri huby. Najprv jeden odstráňte alebo zadajte adresu už pridaného hubu, aby ste vymenili jeho kľúč.",
            remove: "Odstrániť tento hub",
            check: "Skontrolovať huby",
            notChecked: "Kontroluje sa, kým je otvorená stránka AI agenti.",
            checking: "Kontroluje sa…",
            connected: "Pripojené",
            noAccounts: "Pripojené. Hub nezdružuje žiadne predplatné Claude ani Codex.",
            remoteDisabled: "Hub prijíma volania správy iba zo svojho počítača. V jeho konfigurácii nastavte remote-management.allow-remote na true.",
            wrongKey: "Hub tento kľúč odmietol. Pridajte hub znova so správnym kľúčom. Dovtedy sa ho Vorssaint nepýta, pretože hub po piatich nesprávnych kľúčoch zablokuje Mac.",
            blocked: "Hub zablokoval tento Mac po príliš mnohých nesprávnych kľúčoch. Znova ho prijme po pol hodine.",
            managementOff: "API správy hubu je vypnuté. V jeho konfigurácii nastavte remote-management.secret-key.",
            insecure: "macOS povoľuje nešifrovaný http iba na IP adresu alebo názov .local. Použite https alebo IP adresu hubu.",
            unreachable: "K hubu sa nepodarilo pripojiť. Jeho účty si ponechajú posledné údaje.",
            failedFormat: "Hub odpovedal s HTTP %d.",
            accountSignIn: "Prihlásenie hubu do tohto účtu bolo odmietnuté.",
            cardRefused: "Hub kontrolu odmietol. Pozrite Nastavenia.",
            cardUnreachable: "K hubu sa nepodarilo pripojiť.",
            cardFailed: "Hub nemohol odpovedať. Skúste to znova.")
        case .de: return AgentHubStrings(
            title: "CLIProxyAPI-Hubs",
            explanation: "Füge einen CLIProxyAPI-Hub hinzu, damit jedes Claude- und Codex-Abo, das er bündelt, eine Limitkarte erhält. Solange die Seite KI-Agenten geöffnet ist, fragt Vorssaint den Hub etwa alle fünf Minuten ab, und der Hub prüft jedes Konto mit dessen eigener Anmeldung. Es wird kein Prompt gesendet. Die Hub-Konten eines Agenten ersetzen dessen Standard-Limitkarte.",
            keyNote: "Mit dem Verwaltungsschlüssel kann man den Hub auch ändern und seine Anmeldungen herunterladen. Vorssaint speichert ihn in einer privaten Datei auf diesem Mac, lässt ihn aus Einstellungsexporten heraus und sendet ihn nur an den Hub.",
            add: "Hub hinzufügen…",
            address: "Adresse",
            key: "Verwaltungsschlüssel",
            name: "Name (optional)",
            save: "Hinzufügen",
            invalidAddress: "Gib die Adresse des Hubs ein, etwa https://hub.example.net:8317.",
            invalidKey: "Gib den Verwaltungsschlüssel in einer Zeile ein.",
            saveFailed: "Der Hub konnte nicht gespeichert werden. Versuche es erneut.",
            full: "Es passen höchstens vier Hubs. Entferne zuerst einen oder gib die Adresse eines hinzugefügten Hubs ein, um seinen Schlüssel zu ersetzen.",
            remove: "Diesen Hub entfernen",
            check: "Hubs prüfen",
            notChecked: "Wird geprüft, solange die Seite KI-Agenten geöffnet ist.",
            checking: "Wird geprüft…",
            connected: "Verbunden",
            noAccounts: "Verbunden. Der Hub bündelt kein Claude- oder Codex-Abo.",
            remoteDisabled: "Der Hub nimmt Verwaltungsaufrufe nur vom eigenen Rechner an. Setze remote-management.allow-remote in seiner Konfiguration auf true.",
            wrongKey: "Der Hub hat diesen Schlüssel abgelehnt. Füge den Hub mit dem richtigen Schlüssel erneut hinzu. Bis dahin fragt Vorssaint nicht mehr, weil der Hub einen Mac nach fünf falschen Schlüsseln sperrt.",
            blocked: "Der Hub hat diesen Mac nach zu vielen falschen Schlüsseln gesperrt. Nach einer halben Stunde nimmt er ihn wieder an.",
            managementOff: "Die Verwaltungs-API des Hubs ist aus. Setze remote-management.secret-key in seiner Konfiguration.",
            insecure: "macOS erlaubt unverschlüsseltes http nur zu einer IP-Adresse oder einem .local-Namen. Verwende https oder die IP-Adresse des Hubs.",
            unreachable: "Der Hub ist nicht erreichbar. Seine Konten behalten ihre letzten Werte.",
            failedFormat: "Der Hub antwortete mit HTTP %d.",
            accountSignIn: "Die Anmeldung des Hubs für dieses Konto wurde abgelehnt.",
            cardRefused: "Der Hub hat die Prüfung abgelehnt. Siehe Einstellungen.",
            cardUnreachable: "Der Hub ist nicht erreichbar.",
            cardFailed: "Der Hub konnte nicht antworten. Versuche es erneut.")
        case .fr: return AgentHubStrings(
            title: "Hubs CLIProxyAPI",
            explanation: "Ajoutez un hub CLIProxyAPI pour donner une carte de limites à chaque abonnement Claude et Codex qu’il regroupe. Tant que la page Agents IA est ouverte, Vorssaint interroge le hub environ toutes les cinq minutes, et le hub vérifie chaque compte avec sa propre connexion. Aucune requête n’est envoyée. Les comptes du hub d’un agent remplacent sa carte de limites par défaut.",
            keyNote: "La clé de gestion permet aussi à qui la détient de modifier le hub et de télécharger ses connexions. Vorssaint la garde dans un fichier privé sur ce Mac, l’exclut des exportations de réglages et ne l’envoie qu’au hub.",
            add: "Ajouter un hub…",
            address: "Adresse",
            key: "Clé de gestion",
            name: "Nom (facultatif)",
            save: "Ajouter",
            invalidAddress: "Saisissez l’adresse du hub, par exemple https://hub.example.net:8317.",
            invalidKey: "Saisissez la clé de gestion sur une seule ligne.",
            saveFailed: "Impossible d’enregistrer le hub. Réessayez.",
            full: "Quatre hubs au plus. Supprimez-en un d’abord, ou saisissez l’adresse d’un hub déjà ajouté pour remplacer sa clé.",
            remove: "Supprimer ce hub",
            check: "Vérifier les hubs",
            notChecked: "Vérifié tant que la page Agents IA est ouverte.",
            checking: "Vérification…",
            connected: "Connecté",
            noAccounts: "Connecté. Le hub ne regroupe aucun abonnement Claude ou Codex.",
            remoteDisabled: "Le hub n’accepte les appels de gestion que depuis sa propre machine. Réglez remote-management.allow-remote sur true dans sa configuration.",
            wrongKey: "Le hub a refusé cette clé. Ajoutez de nouveau le hub avec la bonne clé. D’ici là, Vorssaint ne l’interroge plus, car le hub bloque un Mac après cinq mauvaises clés.",
            blocked: "Le hub a bloqué ce Mac après trop de mauvaises clés. Il l’accepte de nouveau au bout d’une demi-heure.",
            managementOff: "L’API de gestion du hub est désactivée. Définissez remote-management.secret-key dans sa configuration.",
            insecure: "macOS n’autorise le http non chiffré que vers une adresse IP ou un nom .local. Utilisez https ou l’adresse IP du hub.",
            unreachable: "Impossible de joindre le hub. Ses comptes gardent leurs dernières mesures.",
            failedFormat: "Le hub a répondu avec HTTP %d.",
            accountSignIn: "La connexion du hub à ce compte a été refusée.",
            cardRefused: "Le hub a refusé la vérification. Voir Réglages.",
            cardUnreachable: "Impossible de joindre le hub.",
            cardFailed: "Le hub n’a pas pu répondre. Réessayez.")
        case .it: return AgentHubStrings(
            title: "Hub CLIProxyAPI",
            explanation: "Aggiungi un hub CLIProxyAPI per dare una scheda dei limiti a ogni abbonamento Claude e Codex che raccoglie. Mentre la pagina Agenti IA è aperta, Vorssaint interroga l’hub circa ogni cinque minuti, e l’hub controlla ogni account con il suo accesso. Non viene inviato alcun prompt. Gli account dell’hub di un agente prendono il posto della sua scheda dei limiti predefinita.",
            keyNote: "La chiave di gestione permette anche a chi la possiede di modificare l’hub e scaricarne gli accessi. Vorssaint la conserva in un file privato su questo Mac, la esclude dalle esportazioni delle impostazioni e la invia solo all’hub.",
            add: "Aggiungi hub…",
            address: "Indirizzo",
            key: "Chiave di gestione",
            name: "Nome (facoltativo)",
            save: "Aggiungi",
            invalidAddress: "Inserisci l’indirizzo dell’hub, ad esempio https://hub.example.net:8317.",
            invalidKey: "Inserisci la chiave di gestione su una sola riga.",
            saveFailed: "Impossibile salvare l’hub. Riprova.",
            full: "Ci stanno al massimo quattro hub. Rimuovine prima uno oppure inserisci l’indirizzo di un hub già aggiunto per sostituirne la chiave.",
            remove: "Rimuovi questo hub",
            check: "Controlla hub",
            notChecked: "Controllato mentre la pagina Agenti IA è aperta.",
            checking: "Controllo…",
            connected: "Connesso",
            noAccounts: "Connesso. L’hub non raccoglie alcun abbonamento Claude o Codex.",
            remoteDisabled: "L’hub accetta chiamate di gestione solo dalla propria macchina. Imposta remote-management.allow-remote su true nella sua configurazione.",
            wrongKey: "L’hub ha rifiutato questa chiave. Aggiungi di nuovo l’hub con la chiave giusta. Fino ad allora Vorssaint smette di interrogarlo, perché l’hub blocca un Mac dopo cinque chiavi errate.",
            blocked: "L’hub ha bloccato questo Mac dopo troppe chiavi errate. Lo accetterà di nuovo dopo mezz’ora.",
            managementOff: "L’API di gestione dell’hub è disattivata. Imposta remote-management.secret-key nella sua configurazione.",
            insecure: "macOS consente http non cifrato solo verso un indirizzo IP o un nome .local. Usa https o l’indirizzo IP dell’hub.",
            unreachable: "Impossibile raggiungere l’hub. I suoi account mantengono le ultime letture.",
            failedFormat: "L’hub ha risposto con HTTP %d.",
            accountSignIn: "L’accesso dell’hub a questo account è stato rifiutato.",
            cardRefused: "L’hub ha rifiutato il controllo. Vedi Impostazioni.",
            cardUnreachable: "Impossibile raggiungere l’hub.",
            cardFailed: "L’hub non ha potuto rispondere. Riprova.")
        case .ja: return AgentHubStrings(
            title: "CLIProxyAPIハブ",
            explanation: "CLIProxyAPIハブを追加すると、ハブがまとめているClaudeとCodexのサブスクリプションごとに上限カードが表示されます。AIエージェントのページを開いている間、Vorssaintが約5分ごとにハブに問い合わせ、ハブは各アカウント自身のサインインで確認します。プロンプトは送信されません。エージェントのハブアカウントは、そのエージェントの標準の上限カードの代わりに表示されます。",
            keyNote: "管理キーがあれば、ハブの変更やサインイン情報のダウンロードもできます。VorssaintはこのキーをこのMacの非公開ファイルに保存し、設定の書き出しには含めず、ハブにだけ送信します。",
            add: "ハブを追加…",
            address: "アドレス",
            key: "管理キー",
            name: "名前（任意）",
            save: "追加",
            invalidAddress: "ハブのアドレスを入力してください（例: https://hub.example.net:8317）。",
            invalidKey: "管理キーを1行で入力してください。",
            saveFailed: "ハブを保存できませんでした。もう一度お試しください。",
            full: "ハブは4つまで追加できます。先に1つ削除するか、追加済みのハブのアドレスを入力してキーを置き換えてください。",
            remove: "このハブを削除",
            check: "ハブを確認",
            notChecked: "AIエージェントのページを開いている間に確認されます。",
            checking: "確認中…",
            connected: "接続済み",
            noAccounts: "接続済みです。このハブにはClaudeやCodexのサブスクリプションがありません。",
            remoteDisabled: "ハブは自身のマシンからの管理呼び出しだけを受け付けています。設定でremote-management.allow-remoteをtrueにしてください。",
            wrongKey: "ハブがこのキーを拒否しました。正しいキーでハブを追加し直してください。ハブは誤ったキーが5回続くとMacをブロックするため、それまでVorssaintは問い合わせを止めます。",
            blocked: "誤ったキーが多すぎたため、ハブがこのMacをブロックしました。30分後に再び受け付けます。",
            managementOff: "ハブの管理APIがオフです。設定でremote-management.secret-keyを設定してください。",
            insecure: "macOSでは暗号化されていないhttpはIPアドレスか.localの名前にのみ使えます。httpsかハブのIPアドレスを使ってください。",
            unreachable: "ハブに接続できませんでした。各アカウントは最後の値を保持します。",
            failedFormat: "ハブがHTTP %dで応答しました。",
            accountSignIn: "このアカウントへのハブのサインインが拒否されました。",
            cardRefused: "ハブが確認を拒否しました。設定を確認してください。",
            cardUnreachable: "ハブに接続できませんでした。",
            cardFailed: "ハブが応答できませんでした。もう一度お試しください。")
        case .ko: return AgentHubStrings(
            title: "CLIProxyAPI 허브",
            explanation: "CLIProxyAPI 허브를 추가하면 허브가 묶어 둔 Claude와 Codex 구독마다 한도 카드가 표시됩니다. AI 에이전트 페이지가 열려 있는 동안 Vorssaint가 약 5분마다 허브에 묻고, 허브는 각 계정을 그 계정의 로그인으로 확인합니다. 프롬프트는 보내지 않습니다. 에이전트의 허브 계정이 해당 에이전트의 기본 한도 카드를 대신합니다.",
            keyNote: "관리 키가 있으면 허브를 변경하고 로그인 정보를 내려받을 수도 있습니다. Vorssaint는 이 키를 이 Mac의 비공개 파일에 보관하고, 설정 내보내기에서 제외하며, 허브에만 보냅니다.",
            add: "허브 추가…",
            address: "주소",
            key: "관리 키",
            name: "이름(선택 사항)",
            save: "추가",
            invalidAddress: "허브 주소를 입력하세요. 예: https://hub.example.net:8317",
            invalidKey: "관리 키를 한 줄로 입력하세요.",
            saveFailed: "허브를 저장하지 못했습니다. 다시 시도하세요.",
            full: "허브는 최대 네 개까지 추가할 수 있습니다. 먼저 하나를 제거하거나, 이미 추가한 허브의 주소를 입력해 키를 바꾸세요.",
            remove: "이 허브 제거",
            check: "허브 확인",
            notChecked: "AI 에이전트 페이지가 열려 있는 동안 확인합니다.",
            checking: "확인 중…",
            connected: "연결됨",
            noAccounts: "연결되었습니다. 허브에 Claude나 Codex 구독이 없습니다.",
            remoteDisabled: "허브가 자체 컴퓨터에서 오는 관리 요청만 받습니다. 설정에서 remote-management.allow-remote를 true로 지정하세요.",
            wrongKey: "허브가 이 키를 거부했습니다. 올바른 키로 허브를 다시 추가하세요. 허브는 잘못된 키가 다섯 번 오면 Mac을 차단하므로, 그때까지 Vorssaint는 묻지 않습니다.",
            blocked: "잘못된 키가 너무 많아 허브가 이 Mac을 차단했습니다. 30분 뒤에 다시 받아 줍니다.",
            managementOff: "허브의 관리 API가 꺼져 있습니다. 설정에서 remote-management.secret-key를 지정하세요.",
            insecure: "macOS는 암호화되지 않은 http를 IP 주소나 .local 이름에만 허용합니다. https나 허브의 IP 주소를 사용하세요.",
            unreachable: "허브에 연결할 수 없습니다. 계정은 마지막 값을 유지합니다.",
            failedFormat: "허브가 HTTP %d(으)로 응답했습니다.",
            accountSignIn: "이 계정에 대한 허브의 로그인이 거부되었습니다.",
            cardRefused: "허브가 확인을 거부했습니다. 설정을 확인하세요.",
            cardUnreachable: "허브에 연결할 수 없습니다.",
            cardFailed: "허브가 응답하지 못했습니다. 다시 시도하세요.")
        case .uk: return AgentHubStrings(
            title: "Хаби CLIProxyAPI",
            explanation: "Додайте хаб CLIProxyAPI, щоб кожна підписка Claude і Codex, яку він об’єднує, мала картку лімітів. Поки відкрита сторінка «ШІ-агенти», Vorssaint опитує хаб приблизно раз на п’ять хвилин, а хаб перевіряє кожен обліковий запис із його власним входом. Запити до моделі не надсилаються. Облікові записи хаба замінюють стандартну картку лімітів свого агента.",
            keyNote: "Ключ керування також дає його власнику змогу змінювати хаб і завантажувати його входи. Vorssaint зберігає його в закритому файлі на цьому Mac, не додає до експорту налаштувань і надсилає лише хабу.",
            add: "Додати хаб…",
            address: "Адреса",
            key: "Ключ керування",
            name: "Назва (необов’язково)",
            save: "Додати",
            invalidAddress: "Введіть адресу хаба, наприклад https://hub.example.net:8317.",
            invalidKey: "Введіть ключ керування одним рядком.",
            saveFailed: "Не вдалося зберегти хаб. Спробуйте ще раз.",
            full: "Можна додати не більше чотирьох хабів. Спершу видаліть один або введіть адресу вже доданого хаба, щоб замінити його ключ.",
            remove: "Видалити цей хаб",
            check: "Перевірити хаби",
            notChecked: "Перевіряється, поки відкрита сторінка «ШІ-агенти».",
            checking: "Перевірка…",
            connected: "Підключено",
            noAccounts: "Підключено. Хаб не об’єднує жодної підписки Claude чи Codex.",
            remoteDisabled: "Хаб приймає запити керування лише зі свого комп’ютера. Задайте remote-management.allow-remote: true у його конфігурації.",
            wrongKey: "Хаб відхилив цей ключ. Додайте хаб знову з правильним ключем. Доти Vorssaint не звертається до нього, бо після п’яти неправильних ключів хаб блокує Mac.",
            blocked: "Хаб заблокував цей Mac після забагатьох неправильних ключів. Через пів години він знову його прийме.",
            managementOff: "API керування хаба вимкнено. Задайте remote-management.secret-key у його конфігурації.",
            insecure: "macOS дозволяє звичайний http лише для IP-адреси або імені .local. Використовуйте https або IP-адресу хаба.",
            unreachable: "Не вдалося зв’язатися з хабом. Його облікові записи зберігають останні показники.",
            failedFormat: "Хаб відповів кодом HTTP %d.",
            accountSignIn: "Вхід хаба в цей обліковий запис відхилено.",
            cardRefused: "Хаб відхилив перевірку. Відкрийте налаштування.",
            cardUnreachable: "Не вдалося зв’язатися з хабом.",
            cardFailed: "Хаб не зміг відповісти. Спробуйте ще раз.")
        case .zhHans: return AgentHubStrings(
            title: "CLIProxyAPI 服务器",
            explanation: "添加 CLIProxyAPI 服务器后，它汇集的每个 Claude 和 Codex 订阅都会有自己的额度卡片。AI 智能体页面打开时，Vorssaint 大约每五分钟询问一次服务器，服务器用各账户自己的登录信息检查。不会发送提示。智能体的服务器账户会取代它的默认额度卡片。",
            keyNote: "持有管理密钥的人还可以更改服务器并下载其中的登录信息。Vorssaint 将它保存在这台 Mac 上的私有文件中，不会放入设置导出，只发送给该服务器。",
            add: "添加服务器…",
            address: "地址",
            key: "管理密钥",
            name: "名称（可选）",
            save: "添加",
            invalidAddress: "请输入服务器地址，例如 https://hub.example.net:8317。",
            invalidKey: "请将管理密钥输入为一行。",
            saveFailed: "无法保存服务器，请重试。",
            full: "最多可添加四个服务器。请先移除一个，或输入已添加服务器的地址以替换其密钥。",
            remove: "移除此服务器",
            check: "检查服务器",
            notChecked: "AI 智能体页面打开时检查。",
            checking: "正在检查…",
            connected: "已连接",
            noAccounts: "已连接。该服务器没有汇集任何 Claude 或 Codex 订阅。",
            remoteDisabled: "服务器只接受来自其本机的管理请求。请在其配置中将 remote-management.allow-remote 设为 true。",
            wrongKey: "服务器拒绝了此密钥。请用正确的密钥重新添加服务器。在此之前 Vorssaint 不再询问，因为五次错误密钥后服务器会封锁这台 Mac。",
            blocked: "错误密钥过多，服务器已封锁这台 Mac。半小时后会重新接受。",
            managementOff: "服务器的管理 API 已关闭。请在其配置中设置 remote-management.secret-key。",
            insecure: "macOS 只允许以未加密的 http 连接 IP 地址或 .local 名称。请使用 https 或服务器的 IP 地址。",
            unreachable: "无法连接服务器。其账户保留最后的读数。",
            failedFormat: "服务器返回了 HTTP %d。",
            accountSignIn: "服务器对此账户的登录被拒绝。",
            cardRefused: "服务器拒绝了检查。请查看设置。",
            cardUnreachable: "无法连接服务器。",
            cardFailed: "服务器无法响应，请重试。")
        case .zhTW: return AgentHubStrings(
            title: "CLIProxyAPI 伺服器",
            explanation: "加入 CLIProxyAPI 伺服器後，它匯集的每個 Claude 和 Codex 訂閱都會有自己的額度卡片。AI 代理頁面開啟時，Vorssaint 大約每五分鐘詢問一次伺服器，伺服器會用各帳號自己的登入資訊檢查。不會傳送提示。代理的伺服器帳號會取代它的預設額度卡片。",
            keyNote: "持有管理金鑰的人也能變更伺服器並下載其中的登入資訊。Vorssaint 會將它存放在這台 Mac 上的私人檔案中，不放入設定匯出，只傳送給該伺服器。",
            add: "加入伺服器…",
            address: "位址",
            key: "管理金鑰",
            name: "名稱（選填）",
            save: "加入",
            invalidAddress: "請輸入伺服器位址，例如 https://hub.example.net:8317。",
            invalidKey: "請將管理金鑰輸入成一行。",
            saveFailed: "無法儲存伺服器，請再試一次。",
            full: "最多可加入四個伺服器。請先移除一個，或輸入已加入伺服器的位址以替換其金鑰。",
            remove: "移除此伺服器",
            check: "檢查伺服器",
            notChecked: "AI 代理頁面開啟時檢查。",
            checking: "正在檢查…",
            connected: "已連線",
            noAccounts: "已連線。此伺服器沒有匯集任何 Claude 或 Codex 訂閱。",
            remoteDisabled: "伺服器只接受來自其本機的管理請求。請在其設定中將 remote-management.allow-remote 設為 true。",
            wrongKey: "伺服器拒絕了此金鑰。請用正確的金鑰重新加入伺服器。在此之前 Vorssaint 不再詢問，因為五次錯誤金鑰後伺服器會封鎖這台 Mac。",
            blocked: "錯誤金鑰太多，伺服器已封鎖這台 Mac。半小時後會重新接受。",
            managementOff: "伺服器的管理 API 已關閉。請在其設定中設定 remote-management.secret-key。",
            insecure: "macOS 只允許以未加密的 http 連線至 IP 位址或 .local 名稱。請使用 https 或伺服器的 IP 位址。",
            unreachable: "無法連線至伺服器。其帳號會保留最後的讀數。",
            failedFormat: "伺服器回應了 HTTP %d。",
            accountSignIn: "伺服器對此帳號的登入遭到拒絕。",
            cardRefused: "伺服器拒絕了檢查。請查看設定。",
            cardUnreachable: "無法連線至伺服器。",
            cardFailed: "伺服器無法回應，請再試一次。")
        case .zhHK: return AgentHubStrings(
            title: "CLIProxyAPI 伺服器",
            explanation: "加入 CLIProxyAPI 伺服器後，它匯集的每個 Claude 和 Codex 訂閱都會有自己的額度卡片。AI 代理頁面開啟時，Vorssaint 大約每五分鐘詢問一次伺服器，伺服器會用各帳戶自己的登入資料檢查。不會傳送提示。代理的伺服器帳戶會取代它的預設額度卡片。",
            keyNote: "持有管理金鑰的人亦可更改伺服器並下載其中的登入資料。Vorssaint 會將它存放在這部 Mac 上的私人檔案中，不放入設定匯出，只傳送給該伺服器。",
            add: "加入伺服器…",
            address: "地址",
            key: "管理金鑰",
            name: "名稱（選填）",
            save: "加入",
            invalidAddress: "請輸入伺服器地址，例如 https://hub.example.net:8317。",
            invalidKey: "請將管理金鑰輸入成一行。",
            saveFailed: "無法儲存伺服器，請再試一次。",
            full: "最多可加入四個伺服器。請先移除一個，或輸入已加入伺服器的地址以替換其金鑰。",
            remove: "移除此伺服器",
            check: "檢查伺服器",
            notChecked: "AI 代理頁面開啟時檢查。",
            checking: "正在檢查…",
            connected: "已連線",
            noAccounts: "已連線。此伺服器沒有匯集任何 Claude 或 Codex 訂閱。",
            remoteDisabled: "伺服器只接受來自其本機的管理請求。請在其設定中將 remote-management.allow-remote 設為 true。",
            wrongKey: "伺服器拒絕了此金鑰。請用正確的金鑰重新加入伺服器。在此之前 Vorssaint 不再詢問，因為五次錯誤金鑰後伺服器會封鎖這部 Mac。",
            blocked: "錯誤金鑰太多，伺服器已封鎖這部 Mac。半小時後會重新接受。",
            managementOff: "伺服器的管理 API 已關閉。請在其設定中設定 remote-management.secret-key。",
            insecure: "macOS 只容許以未加密的 http 連線至 IP 地址或 .local 名稱。請使用 https 或伺服器的 IP 地址。",
            unreachable: "無法連線至伺服器。其帳戶會保留最後的讀數。",
            failedFormat: "伺服器回應了 HTTP %d。",
            accountSignIn: "伺服器對此帳戶的登入遭到拒絕。",
            cardRefused: "伺服器拒絕了檢查。請查看設定。",
            cardUnreachable: "無法連線至伺服器。",
            cardFailed: "伺服器無法回應，請再試一次。")
        }
    }
}
