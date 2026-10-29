// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardSyncStrings {
    let enable: String
    let content: String
    let textOnly: String
    let textAndImages: String
    let caption: String
    let privacyNote: String
    /// Replace the history's "stays on this Mac" caption and note while
    /// sync is on.
    let historyCaption: String
    let localNote: String
    let checking: String
    let noAccount: String
    let unavailable: String
    let storageFull: String
    let syncedFormat: String
    let otherMacsFormat: String
    /// The history window's status line.
    let statusLabel: String
    let statusSyncedFormat: String
    let statusJustNow: String
    let statusSyncing: String
    let statusChecking: String
    let statusNoAccount: String
    let statusUnavailable: String
    let statusStorageFull: String
    let statusHelp: String
}

extension FeatureStrings {
    static func clipboardSync(_ language: AppLanguage) -> ClipboardSyncStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension ClipboardSyncStrings {
    static let enUS = ClipboardSyncStrings(
        enable: "Sync history with your other Macs through iCloud",
        content: "Sync",
        textOnly: "Text only",
        textAndImages: "Text and images",
        caption: "Items copied on this Mac also show up on your other Macs signed in to the same Apple Account, through your own iCloud account. Deleting or clearing items removes them on every Mac. Anything the history skips is never synced, and copied files and very large items stay on this Mac.",
        privacyNote: "Synced text is encrypted on this Mac before it reaches iCloud, with keys from your iCloud Keychain; images are protected like the rest of your iCloud data. Turning sync off removes this Mac’s copy from iCloud; your other Macs keep what they already received.",
        historyCaption: "Stores copied text so you can reuse it later, on this Mac and your other Macs. It can be cleared anytime.",
        localNote: "Saved items are also copied to your iCloud account while sync is on. Very large items are ignored.",
        checking: "Checking iCloud…",
        noAccount: "Sign in to iCloud in System Settings to sync.",
        unavailable: "iCloud can’t be reached right now. Vorssaint will try again.",
        storageFull: "Your iCloud storage is full, so new items can’t sync.",
        syncedFormat: "Last synced at %@",
        otherMacsFormat: "Other Macs: %d",
        statusLabel: "iCloud sync",
        statusSyncedFormat: "Synced %@",
        statusJustNow: "Synced just now",
        statusSyncing: "Syncing…",
        statusChecking: "Checking…",
        statusNoAccount: "Not signed in to iCloud",
        statusUnavailable: "Can’t reach iCloud",
        statusStorageFull: "iCloud storage is full",
        statusHelp: "Syncs a few seconds after each change on this Mac and at least once a minute, picking up the other Macs’ changes each time. Click to sync now."
    )

    static let ptBR = ClipboardSyncStrings(
        enable: "Sincronizar o histórico com seus outros Macs pelo iCloud",
        content: "Sincronizar",
        textOnly: "Só texto",
        textAndImages: "Texto e imagens",
        caption: "Itens copiados neste Mac também aparecem nos seus outros Macs conectados à mesma Conta Apple, pela sua própria conta do iCloud. Apagar ou limpar itens os remove de todos os Macs. Nada que o histórico ignora é sincronizado, e arquivos copiados e itens muito grandes ficam neste Mac.",
        privacyNote: "O texto sincronizado é criptografado neste Mac antes de chegar ao iCloud, com chaves do seu Porta-chaves do iCloud; as imagens são protegidas como o restante dos seus dados do iCloud. Desativar a sincronização remove a cópia deste Mac do iCloud; seus outros Macs mantêm o que já receberam.",
        historyCaption: "Guarda textos copiados para reutilizar depois, neste Mac e nos seus outros Macs. Pode ser apagado a qualquer momento.",
        localNote: "Os itens guardados também vão para a sua conta do iCloud enquanto a sincronização está ativada. Itens muito grandes são ignorados.",
        checking: "Verificando o iCloud…",
        noAccount: "Inicie sessão no iCloud nos Ajustes do Sistema para sincronizar.",
        unavailable: "O iCloud não está disponível agora. O Vorssaint tentará de novo.",
        storageFull: "Seu armazenamento do iCloud está cheio, então novos itens não podem ser sincronizados.",
        syncedFormat: "Última sincronização às %@",
        otherMacsFormat: "Outros Macs: %d",
        statusLabel: "Sincronização do iCloud",
        statusSyncedFormat: "Sincronizado %@",
        statusJustNow: "Sincronizado agora mesmo",
        statusSyncing: "Sincronizando…",
        statusChecking: "Verificando…",
        statusNoAccount: "Sem sessão no iCloud",
        statusUnavailable: "Não foi possível acessar o iCloud",
        statusStorageFull: "O armazenamento do iCloud está cheio",
        statusHelp: "Sincroniza alguns segundos após cada alteração neste Mac e pelo menos uma vez por minuto, trazendo as alterações dos outros Macs a cada vez. Clique para sincronizar agora."
    )

    static let tr = ClipboardSyncStrings(
        enable: "Geçmişi iCloud ile diğer Mac’lerinizle eşzamanla",
        content: "Eşzamanla",
        textOnly: "Yalnızca metin",
        textAndImages: "Metin ve görseller",
        caption: "Bu Mac’te kopyalanan öğeler, kendi iCloud hesabınız aracılığıyla aynı Apple Hesabı’yla giriş yapılmış diğer Mac’lerinizde de görünür. Öğeleri silmek ya da temizlemek onları her Mac’ten kaldırır. Geçmişin atladığı hiçbir şey eşzamanlanmaz; kopyalanan dosyalar ve çok büyük öğeler bu Mac’te kalır.",
        privacyNote: "Eşzamanlanan metin, iCloud’a ulaşmadan önce bu Mac’te iCloud Anahtar Zinciri’nizdeki anahtarlarla şifrelenir; görseller iCloud’daki diğer verileriniz gibi korunur. Eşzamanlamayı kapatmak bu Mac’in kopyasını iCloud’dan kaldırır; diğer Mac’leriniz aldıklarını saklar.",
        historyCaption: "Kopyalanan metinleri daha sonra yeniden kullanabilmeniz için bu Mac’te ve diğer Mac’lerinizde saklar. İstediğiniz zaman temizlenebilir.",
        localNote: "Eşzamanlama açıkken kaydedilen öğeler iCloud hesabınıza da kopyalanır. Çok büyük öğeler yok sayılır.",
        checking: "iCloud denetleniyor…",
        noAccount: "Eşzamanlamak için Sistem Ayarları’ndan iCloud’a giriş yapın.",
        unavailable: "iCloud’a şu anda ulaşılamıyor. Vorssaint yeniden deneyecek.",
        storageFull: "iCloud depolama alanınız dolu, bu yüzden yeni öğeler eşzamanlanamıyor.",
        syncedFormat: "Son eşzamanlama: %@",
        otherMacsFormat: "Diğer Mac’ler: %d",
        statusLabel: "iCloud eşzamanlama",
        statusSyncedFormat: "Eşzamanlandı: %@",
        statusJustNow: "Az önce eşzamanlandı",
        statusSyncing: "Eşzamanlanıyor…",
        statusChecking: "Denetleniyor…",
        statusNoAccount: "iCloud’a giriş yapılmamış",
        statusUnavailable: "iCloud’a ulaşılamıyor",
        statusStorageFull: "iCloud depolama alanı dolu",
        statusHelp: "Bu Mac’teki her değişiklikten birkaç saniye sonra ve en az dakikada bir eşzamanlar; her seferinde diğer Mac’lerin değişikliklerini de alır. Hemen eşzamanlamak için tıklayın."
    )

    static let ru = ClipboardSyncStrings(
        enable: "Синхронизировать историю с другими Mac через iCloud",
        content: "Синхронизировать",
        textOnly: "Только текст",
        textAndImages: "Текст и изображения",
        caption: "Элементы, скопированные на этом Mac, появляются и на других ваших Mac с тем же Аккаунтом Apple через вашу учётную запись iCloud. Удаление или очистка элементов убирает их на всех Mac. То, что история пропускает, никогда не синхронизируется, а скопированные файлы и очень большие элементы остаются на этом Mac.",
        privacyNote: "Синхронизируемый текст шифруется на этом Mac ещё до отправки в iCloud ключами из вашей Связки ключей iCloud; изображения защищены так же, как остальные ваши данные в iCloud. Если выключить синхронизацию, копия этого Mac будет удалена из iCloud; другие Mac сохранят то, что уже получили.",
        historyCaption: "Сохраняет скопированный текст на этом Mac и других ваших Mac, чтобы вы могли использовать его позже. Его можно очистить в любой момент.",
        localNote: "Пока синхронизация включена, сохранённые элементы также копируются в ваш iCloud. Слишком большие элементы игнорируются.",
        checking: "Проверка iCloud…",
        noAccount: "Войдите в iCloud в Системных настройках, чтобы синхронизировать.",
        unavailable: "iCloud сейчас недоступен. Vorssaint попробует снова.",
        storageFull: "Хранилище iCloud заполнено, поэтому новые элементы не синхронизируются.",
        syncedFormat: "Последняя синхронизация: %@",
        otherMacsFormat: "Других Mac: %d",
        statusLabel: "Синхронизация iCloud",
        statusSyncedFormat: "Синхронизировано %@",
        statusJustNow: "Синхронизировано только что",
        statusSyncing: "Синхронизация…",
        statusChecking: "Проверка…",
        statusNoAccount: "Вход в iCloud не выполнен",
        statusUnavailable: "Нет доступа к iCloud",
        statusStorageFull: "Хранилище iCloud заполнено",
        statusHelp: "Синхронизирует через несколько секунд после каждого изменения на этом Mac и не реже раза в минуту, каждый раз получая изменения с других Mac. Нажмите, чтобы синхронизировать сейчас."
    )

    static let es = ClipboardSyncStrings(
        enable: "Sincronizar el historial con tus otros Mac a través de iCloud",
        content: "Sincronizar",
        textOnly: "Solo texto",
        textAndImages: "Texto e imágenes",
        caption: "Los elementos copiados en este Mac también aparecen en tus otros Mac con la misma cuenta de Apple, a través de tu propia cuenta de iCloud. Al eliminar o borrar elementos, desaparecen de todos los Mac. Nada de lo que el historial omite se sincroniza, y los archivos copiados y los elementos muy grandes se quedan en este Mac.",
        privacyNote: "El texto sincronizado se cifra en este Mac antes de llegar a iCloud, con claves de tu llavero de iCloud; las imágenes se protegen como el resto de tus datos de iCloud. Al desactivar la sincronización se elimina de iCloud la copia de este Mac; tus otros Mac conservan lo que ya recibieron.",
        historyCaption: "Guarda el texto copiado para reutilizarlo después, en este Mac y en tus otros Mac. Se puede borrar cuando quieras.",
        localNote: "Mientras la sincronización está activada, los elementos guardados también se copian en tu cuenta de iCloud. Los elementos muy grandes se ignoran.",
        checking: "Comprobando iCloud…",
        noAccount: "Inicia sesión en iCloud en Ajustes del Sistema para sincronizar.",
        unavailable: "iCloud no está disponible ahora. Vorssaint lo intentará de nuevo.",
        storageFull: "Tu almacenamiento de iCloud está lleno, así que los elementos nuevos no se pueden sincronizar.",
        syncedFormat: "Última sincronización a las %@",
        otherMacsFormat: "Otros Mac: %d",
        statusLabel: "Sincronización con iCloud",
        statusSyncedFormat: "Sincronizado %@",
        statusJustNow: "Sincronizado ahora mismo",
        statusSyncing: "Sincronizando…",
        statusChecking: "Comprobando…",
        statusNoAccount: "No has iniciado sesión en iCloud",
        statusUnavailable: "No se puede acceder a iCloud",
        statusStorageFull: "El almacenamiento de iCloud está lleno",
        statusHelp: "Sincroniza unos segundos después de cada cambio en este Mac y al menos una vez por minuto, recogiendo cada vez los cambios de los otros Mac. Haz clic para sincronizar ahora."
    )

    static let sk = ClipboardSyncStrings(
        enable: "Synchronizovať históriu s ostatnými Macmi cez iCloud",
        content: "Synchronizovať",
        textOnly: "Iba text",
        textAndImages: "Text a obrázky",
        caption: "Položky skopírované na tomto Macu sa cez váš vlastný účet iCloud zobrazia aj na vašich ďalších Macoch prihlásených do rovnakého Apple účtu. Vymazanie alebo vyčistenie položiek ich odstráni na každom Macu. Nič, čo história vynecháva, sa nesynchronizuje a skopírované súbory a príliš veľké položky zostávajú na tomto Macu.",
        privacyNote: "Synchronizovaný text sa šifruje na tomto Macu ešte pred odoslaním do iCloudu, kľúčmi z vašej iCloud kľúčenky; obrázky sú chránené ako ostatné vaše údaje v iCloude. Vypnutím synchronizácie sa z iCloudu odstráni kópia tohto Macu; ostatné Macy si ponechajú, čo už dostali.",
        historyCaption: "Ukladá skopírovaný text, aby ste ho mohli neskôr znova použiť na tomto Macu aj na ďalších Macoch. Môžete ho kedykoľvek vymazať.",
        localNote: "Kým je synchronizácia zapnutá, uložené položky sa kopírujú aj do vášho účtu iCloud. Príliš veľké položky sa ignorujú.",
        checking: "Kontroluje sa iCloud…",
        noAccount: "Na synchronizáciu sa prihláste do iCloudu v Systémových nastaveniach.",
        unavailable: "iCloud momentálne nie je dostupný. Vorssaint to skúsi znova.",
        storageFull: "Vaše úložisko iCloud je plné, preto sa nové položky nemôžu synchronizovať.",
        syncedFormat: "Naposledy synchronizované o %@",
        otherMacsFormat: "Ďalšie Macy: %d",
        statusLabel: "Synchronizácia cez iCloud",
        statusSyncedFormat: "Synchronizované %@",
        statusJustNow: "Synchronizované práve teraz",
        statusSyncing: "Synchronizuje sa…",
        statusChecking: "Kontroluje sa…",
        statusNoAccount: "Nie ste prihlásení do iCloudu",
        statusUnavailable: "iCloud nie je dostupný",
        statusStorageFull: "Úložisko iCloud je plné",
        statusHelp: "Synchronizuje pár sekúnd po každej zmene na tomto Macu a aspoň raz za minútu, pričom zakaždým prevezme zmeny z ostatných Macov. Kliknutím synchronizujete hneď."
    )

    static let de = ClipboardSyncStrings(
        enable: "Verlauf über iCloud mit deinen anderen Macs synchronisieren",
        content: "Synchronisieren",
        textOnly: "Nur Text",
        textAndImages: "Text und Bilder",
        caption: "Auf diesem Mac kopierte Einträge erscheinen über deinen eigenen iCloud-Account auch auf deinen anderen Macs mit demselben Apple Account. Gelöschte oder geleerte Einträge verschwinden auf jedem Mac. Was der Verlauf auslässt, wird nie synchronisiert, und kopierte Dateien sowie sehr große Einträge bleiben auf diesem Mac.",
        privacyNote: "Synchronisierter Text wird auf diesem Mac verschlüsselt, bevor er iCloud erreicht, mit Schlüsseln aus deinem iCloud-Schlüsselbund; Bilder sind geschützt wie deine anderen iCloud-Daten. Wenn du die Synchronisierung ausschaltest, wird die Kopie dieses Macs aus iCloud entfernt; deine anderen Macs behalten, was sie schon erhalten haben.",
        historyCaption: "Speichert kopierten Text, damit du ihn später auf diesem Mac und deinen anderen Macs wiederverwenden kannst. Er kann jederzeit gelöscht werden.",
        localNote: "Solange die Synchronisierung an ist, werden gespeicherte Einträge auch in deinen iCloud-Account kopiert. Sehr große Inhalte werden ignoriert.",
        checking: "iCloud wird geprüft…",
        noAccount: "Melde dich in den Systemeinstellungen bei iCloud an, um zu synchronisieren.",
        unavailable: "iCloud ist gerade nicht erreichbar. Vorssaint versucht es erneut.",
        storageFull: "Dein iCloud-Speicher ist voll, daher können neue Einträge nicht synchronisiert werden.",
        syncedFormat: "Zuletzt synchronisiert um %@",
        otherMacsFormat: "Andere Macs: %d",
        statusLabel: "iCloud-Synchronisierung",
        statusSyncedFormat: "Synchronisiert %@",
        statusJustNow: "Gerade synchronisiert",
        statusSyncing: "Wird synchronisiert…",
        statusChecking: "Wird geprüft…",
        statusNoAccount: "Nicht bei iCloud angemeldet",
        statusUnavailable: "iCloud nicht erreichbar",
        statusStorageFull: "iCloud-Speicher ist voll",
        statusHelp: "Synchronisiert ein paar Sekunden nach jeder Änderung auf diesem Mac und mindestens einmal pro Minute und holt dabei jedes Mal die Änderungen der anderen Macs. Klicke, um jetzt zu synchronisieren."
    )

    static let fr = ClipboardSyncStrings(
        enable: "Synchroniser l’historique avec vos autres Mac via iCloud",
        content: "Synchroniser",
        textOnly: "Texte uniquement",
        textAndImages: "Texte et images",
        caption: "Les éléments copiés sur ce Mac apparaissent aussi sur vos autres Mac connectés au même compte Apple, grâce à votre propre compte iCloud. Supprimer ou effacer des éléments les retire de chaque Mac. Rien de ce que l’historique ignore n’est synchronisé, et les fichiers copiés ainsi que les éléments très volumineux restent sur ce Mac.",
        privacyNote: "Le texte synchronisé est chiffré sur ce Mac avant d’atteindre iCloud, avec des clés de votre trousseau iCloud. Les images sont protégées comme le reste de vos données iCloud. Désactiver la synchronisation retire d’iCloud la copie de ce Mac. Vos autres Mac conservent ce qu’ils ont déjà reçu.",
        historyCaption: "Enregistre le texte copié pour le réutiliser plus tard, sur ce Mac et vos autres Mac. Il peut être effacé à tout moment.",
        localNote: "Tant que la synchronisation est activée, les éléments enregistrés sont aussi copiés dans votre compte iCloud. Les éléments très volumineux sont ignorés.",
        checking: "Vérification d’iCloud…",
        noAccount: "Connectez-vous à iCloud dans Réglages Système pour synchroniser.",
        unavailable: "iCloud est injoignable pour le moment. Vorssaint réessaiera.",
        storageFull: "Votre stockage iCloud est plein, les nouveaux éléments ne peuvent donc pas être synchronisés.",
        syncedFormat: "Dernière synchronisation à %@",
        otherMacsFormat: "Autres Mac\u{00A0}: %d",
        statusLabel: "Synchronisation iCloud",
        statusSyncedFormat: "Synchronisé %@",
        statusJustNow: "Synchronisé à l’instant",
        statusSyncing: "Synchronisation…",
        statusChecking: "Vérification…",
        statusNoAccount: "Non connecté à iCloud",
        statusUnavailable: "iCloud est injoignable",
        statusStorageFull: "Le stockage iCloud est plein",
        statusHelp: "Synchronise quelques secondes après chaque modification sur ce Mac et au moins une fois par minute, en récupérant à chaque fois les modifications des autres Mac. Cliquez pour synchroniser maintenant."
    )

    static let it = ClipboardSyncStrings(
        enable: "Sincronizza la cronologia con gli altri Mac tramite iCloud",
        content: "Sincronizza",
        textOnly: "Solo testo",
        textAndImages: "Testo e immagini",
        caption: "Gli elementi copiati su questo Mac compaiono anche sugli altri Mac collegati allo stesso Account Apple, tramite il tuo account iCloud. Eliminare o svuotare gli elementi li rimuove da ogni Mac. Nulla di ciò che la cronologia esclude viene sincronizzato, e i file copiati e gli elementi molto grandi restano su questo Mac.",
        privacyNote: "Il testo sincronizzato viene cifrato su questo Mac prima di raggiungere iCloud, con chiavi del tuo portachiavi iCloud; le immagini sono protette come il resto dei tuoi dati iCloud. Disattivando la sincronizzazione, la copia di questo Mac viene rimossa da iCloud; gli altri Mac conservano ciò che hanno già ricevuto.",
        historyCaption: "Salva il testo copiato per riutilizzarlo in seguito, su questo Mac e sugli altri tuoi Mac. Può essere cancellato in qualsiasi momento.",
        localNote: "Finché la sincronizzazione è attiva, gli elementi salvati vengono copiati anche nel tuo account iCloud. Gli elementi molto grandi vengono ignorati.",
        checking: "Controllo di iCloud…",
        noAccount: "Accedi a iCloud in Impostazioni di Sistema per sincronizzare.",
        unavailable: "iCloud non è raggiungibile in questo momento. Vorssaint riproverà.",
        storageFull: "Lo spazio di iCloud è pieno, quindi i nuovi elementi non possono essere sincronizzati.",
        syncedFormat: "Ultima sincronizzazione alle %@",
        otherMacsFormat: "Altri Mac: %d",
        statusLabel: "Sincronizzazione iCloud",
        statusSyncedFormat: "Sincronizzato %@",
        statusJustNow: "Sincronizzato ora",
        statusSyncing: "Sincronizzazione…",
        statusChecking: "Controllo…",
        statusNoAccount: "Accesso a iCloud non eseguito",
        statusUnavailable: "Impossibile raggiungere iCloud",
        statusStorageFull: "Lo spazio di iCloud è pieno",
        statusHelp: "Sincronizza qualche secondo dopo ogni modifica su questo Mac e almeno una volta al minuto, recuperando ogni volta le modifiche degli altri Mac. Fai clic per sincronizzare ora."
    )

    static let ja = ClipboardSyncStrings(
        enable: "iCloudでほかのMacと履歴を同期",
        content: "同期する内容",
        textOnly: "テキストのみ",
        textAndImages: "テキストと画像",
        caption: "このMacでコピーした項目は、あなた自身のiCloudアカウントを通じて、同じApple AccountでサインインしているほかのMacにも表示されます。項目を削除または消去すると、すべてのMacから取り除かれます。履歴が除外するものは同期されず、コピーしたファイルや大きすぎる項目はこのMacに残ります。",
        privacyNote: "同期されるテキストは、iCloudに送られる前にこのMac上でiCloudキーチェーンの鍵を使って暗号化されます。画像はほかのiCloudデータと同じように保護されます。同期をオフにすると、このMacのコピーはiCloudから削除されます。ほかのMacは受け取った項目を保持します。",
        historyCaption: "コピーしたテキストを保存して、このMacとほかのMacであとで再利用できます。いつでも削除できます。",
        localNote: "同期がオンの間、保存した項目はiCloudアカウントにもコピーされます。大きすぎる項目は無視されます。",
        checking: "iCloudを確認中…",
        noAccount: "同期するには、システム設定でiCloudにサインインしてください。",
        unavailable: "現在iCloudに接続できません。Vorssaintがあとで再試行します。",
        storageFull: "iCloudストレージがいっぱいのため、新しい項目を同期できません。",
        syncedFormat: "最終同期: %@",
        otherMacsFormat: "ほかのMac: %d台",
        statusLabel: "iCloud同期",
        statusSyncedFormat: "%@に同期",
        statusJustNow: "たった今同期",
        statusSyncing: "同期中…",
        statusChecking: "確認中…",
        statusNoAccount: "iCloudにサインインしていません",
        statusUnavailable: "iCloudに接続できません",
        statusStorageFull: "iCloudストレージがいっぱいです",
        statusHelp: "このMacで変更があってから数秒後と、少なくとも1分に1回同期し、そのたびにほかのMacの変更も取り込みます。クリックするとすぐに同期します。"
    )

    static let ko = ClipboardSyncStrings(
        enable: "iCloud로 다른 Mac과 기록 동기화",
        content: "동기화 항목",
        textOnly: "텍스트만",
        textAndImages: "텍스트 및 이미지",
        caption: "이 Mac에서 복사한 항목이 사용자 본인의 iCloud 계정을 통해 같은 Apple 계정으로 로그인한 다른 Mac에도 표시됩니다. 항목을 삭제하거나 지우면 모든 Mac에서 제거됩니다. 기록이 건너뛰는 항목은 동기화되지 않으며, 복사한 파일과 너무 큰 항목은 이 Mac에 남습니다.",
        privacyNote: "동기화되는 텍스트는 iCloud에 전송되기 전에 이 Mac에서 iCloud 키체인의 키로 암호화됩니다. 이미지는 다른 iCloud 데이터와 같은 방식으로 보호됩니다. 동기화를 끄면 이 Mac의 사본이 iCloud에서 제거되며, 다른 Mac은 이미 받은 항목을 유지합니다.",
        historyCaption: "복사한 텍스트를 저장하여 이 Mac과 다른 Mac에서 나중에 다시 사용할 수 있습니다. 언제든 지울 수 있습니다.",
        localNote: "동기화가 켜져 있는 동안 저장된 항목이 iCloud 계정에도 복사됩니다. 너무 큰 항목은 무시됩니다.",
        checking: "iCloud 확인 중…",
        noAccount: "동기화하려면 시스템 설정에서 iCloud에 로그인하십시오.",
        unavailable: "지금은 iCloud에 연결할 수 없습니다. Vorssaint가 다시 시도합니다.",
        storageFull: "iCloud 저장 공간이 가득 차서 새 항목을 동기화할 수 없습니다.",
        syncedFormat: "마지막 동기화: %@",
        otherMacsFormat: "다른 Mac: %d대",
        statusLabel: "iCloud 동기화",
        statusSyncedFormat: "%@ 동기화됨",
        statusJustNow: "방금 동기화됨",
        statusSyncing: "동기화 중…",
        statusChecking: "확인 중…",
        statusNoAccount: "iCloud에 로그인되어 있지 않음",
        statusUnavailable: "iCloud에 연결할 수 없음",
        statusStorageFull: "iCloud 저장 공간이 가득 참",
        statusHelp: "이 Mac에서 변경될 때마다 몇 초 후, 그리고 최소 1분에 한 번 동기화하며 그때마다 다른 Mac의 변경 사항도 가져옵니다. 지금 동기화하려면 클릭하십시오."
    )

    static let zhHans = ClipboardSyncStrings(
        enable: "通过 iCloud 与你的其他 Mac 同步历史",
        content: "同步内容",
        textOnly: "仅文本",
        textAndImages: "文本和图片",
        caption: "在这台 Mac 上拷贝的项目会通过你自己的 iCloud 账户，同样出现在登录同一 Apple 账户的其他 Mac 上。删除或清除项目会在每台 Mac 上移除它们。历史记录跳过的内容永远不会同步，拷贝的文件和特别大的项目会留在这台 Mac 上。",
        privacyNote: "同步的文本在发送到 iCloud 之前，会在这台 Mac 上使用你 iCloud 钥匙串中的密钥加密；图片会像你的其他 iCloud 数据一样受到保护。关闭同步会从 iCloud 移除这台 Mac 的副本，你的其他 Mac 会保留已经收到的内容。",
        historyCaption: "保存拷贝的文本，以便稍后在这台 Mac 和你的其他 Mac 上重复使用。可以随时清除。",
        localNote: "开启同步时，保存的项目也会拷贝到你的 iCloud 账户。特别大的内容会被忽略。",
        checking: "正在检查 iCloud…",
        noAccount: "请在系统设置中登录 iCloud 以进行同步。",
        unavailable: "目前无法连接 iCloud。Vorssaint 会再试一次。",
        storageFull: "你的 iCloud 储存空间已满，因此新项目无法同步。",
        syncedFormat: "上次同步：%@",
        otherMacsFormat: "其他 Mac：%d 台",
        statusLabel: "iCloud 同步",
        statusSyncedFormat: "%@同步",
        statusJustNow: "刚刚同步",
        statusSyncing: "正在同步…",
        statusChecking: "正在检查…",
        statusNoAccount: "未登录 iCloud",
        statusUnavailable: "无法连接 iCloud",
        statusStorageFull: "iCloud 储存空间已满",
        statusHelp: "在这台 Mac 上每次更改后几秒以及至少每分钟同步一次，每次都会取回其他 Mac 的更改。点按可立即同步。"
    )

    static let zhTW = ClipboardSyncStrings(
        enable: "透過 iCloud 與你的其他 Mac 同步紀錄",
        content: "同步內容",
        textOnly: "僅文字",
        textAndImages: "文字和圖片",
        caption: "在這台 Mac 上拷貝的項目會透過你自己的 iCloud 帳號，同樣顯示在登入相同 Apple 帳號的其他 Mac 上。刪除或清除項目會在每台 Mac 上移除它們。紀錄略過的內容永遠不會同步，拷貝的檔案和過大的項目會留在這台 Mac 上。",
        privacyNote: "同步的文字在傳送到 iCloud 之前，會在這台 Mac 上使用你 iCloud 鑰匙圈中的密鑰加密；圖片會像你的其他 iCloud 資料一樣受到保護。關閉同步會從 iCloud 移除這台 Mac 的副本，你的其他 Mac 會保留已經收到的內容。",
        historyCaption: "儲存拷貝的文字，以便稍後在這台 Mac 和你的其他 Mac 上重複使用。可以隨時清除。",
        localNote: "開啟同步時，儲存的項目也會拷貝到你的 iCloud 帳號。過大的內容會被略過。",
        checking: "正在檢查 iCloud…",
        noAccount: "請在系統設定中登入 iCloud 以進行同步。",
        unavailable: "目前無法連線至 iCloud。Vorssaint 會再試一次。",
        storageFull: "你的 iCloud 儲存空間已滿，因此新項目無法同步。",
        syncedFormat: "上次同步：%@",
        otherMacsFormat: "其他 Mac：%d 台",
        statusLabel: "iCloud 同步",
        statusSyncedFormat: "%@同步",
        statusJustNow: "剛剛同步",
        statusSyncing: "正在同步…",
        statusChecking: "正在檢查…",
        statusNoAccount: "未登入 iCloud",
        statusUnavailable: "無法連線至 iCloud",
        statusStorageFull: "iCloud 儲存空間已滿",
        statusHelp: "在這台 Mac 上每次更改後幾秒以及至少每分鐘同步一次，每次都會取回其他 Mac 的更改。按一下即可立即同步。"
    )

    static let zhHK = ClipboardSyncStrings(
        enable: "透過 iCloud 與你的其他 Mac 同步記錄",
        content: "同步內容",
        textOnly: "只限文字",
        textAndImages: "文字和圖片",
        caption: "在這部 Mac 上拷貝的項目會透過你自己的 iCloud 帳户，同樣顯示在登入相同 Apple 帳户的其他 Mac 上。刪除或清除項目會在每部 Mac 上移除它們。記錄略過的內容永遠不會同步，拷貝的檔案和過大的項目會留在這部 Mac 上。",
        privacyNote: "同步的文字在傳送到 iCloud 之前，會在這部 Mac 上使用你 iCloud 鑰匙圈中的密鑰加密；圖片會像你的其他 iCloud 資料一樣受到保護。關閉同步會從 iCloud 移除這部 Mac 的副本，你的其他 Mac 會保留已經收到的內容。",
        historyCaption: "儲存拷貝的文字，以便稍後在這部 Mac 和你的其他 Mac 上重複使用。可以隨時清除。",
        localNote: "開啟同步時，儲存的項目亦會拷貝到你的 iCloud 帳户。過大的內容會被略過。",
        checking: "正在檢查 iCloud…",
        noAccount: "請在系統設定中登入 iCloud 以進行同步。",
        unavailable: "目前無法連線至 iCloud。Vorssaint 會再試一次。",
        storageFull: "你的 iCloud 儲存空間已滿，因此新項目無法同步。",
        syncedFormat: "上次同步：%@",
        otherMacsFormat: "其他 Mac：%d 部",
        statusLabel: "iCloud 同步",
        statusSyncedFormat: "%@同步",
        statusJustNow: "剛剛同步",
        statusSyncing: "正在同步…",
        statusChecking: "正在檢查…",
        statusNoAccount: "未登入 iCloud",
        statusUnavailable: "無法連線至 iCloud",
        statusStorageFull: "iCloud 儲存空間已滿",
        statusHelp: "在這部 Mac 上每次更改後幾秒以及至少每分鐘同步一次，每次都會取回其他 Mac 的更改。按一下即可立即同步。"
    )

    static let uk = ClipboardSyncStrings(
        enable: "Синхронізувати історію з іншими Mac через iCloud",
        content: "Синхронізувати",
        textOnly: "Лише текст",
        textAndImages: "Текст і зображення",
        caption: "Елементи, скопійовані на цьому Mac, з’являються й на інших ваших Mac з тим самим обліковим записом Apple через ваш власний обліковий запис iCloud. Видалення або очищення елементів прибирає їх на всіх Mac. Те, що історія пропускає, ніколи не синхронізується, а скопійовані файли й дуже великі елементи залишаються на цьому Mac.",
        privacyNote: "Синхронізований текст шифрується на цьому Mac ще до відправлення в iCloud ключами з вашої Зв’язки ключів iCloud; зображення захищені так само, як інші ваші дані в iCloud. Вимкнення синхронізації видаляє копію цього Mac з iCloud; інші Mac зберігають те, що вже отримали.",
        historyCaption: "Зберігає скопійований текст на цьому Mac та інших ваших Mac, щоб ви могли використати його пізніше. Його можна очистити будь-коли.",
        localNote: "Поки синхронізацію ввімкнено, збережені елементи також копіюються у ваш обліковий запис iCloud. Надто великі елементи ігноруються.",
        checking: "Перевірка iCloud…",
        noAccount: "Увійдіть в iCloud у Системних параметрах, щоб синхронізувати.",
        unavailable: "iCloud зараз недоступний. Vorssaint спробує ще раз.",
        storageFull: "Сховище iCloud заповнене, тому нові елементи не синхронізуються.",
        syncedFormat: "Остання синхронізація: %@",
        otherMacsFormat: "Інших Mac: %d",
        statusLabel: "Синхронізація iCloud",
        statusSyncedFormat: "Синхронізовано %@",
        statusJustNow: "Синхронізовано щойно",
        statusSyncing: "Синхронізація…",
        statusChecking: "Перевірка…",
        statusNoAccount: "Вхід в iCloud не виконано",
        statusUnavailable: "Немає доступу до iCloud",
        statusStorageFull: "Сховище iCloud заповнене",
        statusHelp: "Синхронізує через кілька секунд після кожної зміни на цьому Mac і щонайменше раз на хвилину, щоразу отримуючи зміни з інших Mac. Натисніть, щоб синхронізувати зараз."
    )
}
