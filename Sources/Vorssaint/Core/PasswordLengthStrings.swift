// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PasswordLengthStrings {
    let title: String
    let caption: String
    let shared: String
    let minimum: String
    let none: String
    let disable: String
    let restore: String
    let enable: String
    let refresh: String
    let failed: String
    let continueAction: String
    let confirm: String
}

extension FeatureStrings {
    static func passwordLength(_ language: AppLanguage) -> PasswordLengthStrings {
        switch language {
        case .enUS: return PasswordLengthStrings(
            title: "Login password length",
            caption: "Manage minimum length rules without changing your password. Original rules are saved on this Mac for restoration.",
            shared: "System-wide length rules affect all local accounts.",
            minimum: "Minimum characters",
            none: "No editable minimum-length rule is set. Choose a new minimum to enable a limit.",
            disable: "Remove length requirement…",
            restore: "Restore original requirement…",
            enable: "Set minimum length…",
            refresh: "Refresh",
            failed: "Could not complete this operation. Authorization may have been cancelled, policies may have changed, or this Mac has managed or unsupported rules. Saved recovery is kept.",
            continueAction: "Continue",
            confirm: "Administrator authorization is required. Shorter passwords are easier to guess. Existing passwords are not changed; macOS decides when restored requirements apply. System-wide rules affect all local accounts.")
        case .zhHans: return PasswordLengthStrings(
            title: "登录密码长度",
            caption: "管理最小长度规则，不修改密码。原规则保存在本机，供之后恢复。",
            shared: "系统级长度规则会影响所有本地账户。",
            minimum: "最少字符数",
            none: "未设置可编辑的最小长度规则。请选择新的最小长度以启用限制。",
            disable: "取消长度要求…",
            restore: "恢复原来的要求…",
            enable: "设置最小长度…",
            refresh: "刷新",
            failed: "无法完成操作。可能已取消授权、策略发生变化，或此 Mac 存在受管理或不支持的规则。恢复记录仍会保留。",
            continueAction: "继续",
            confirm: "需要管理员授权。较短的密码更容易被猜中。现有密码不会被修改；恢复的要求何时生效由 macOS 决定。系统级规则会影响所有本地账户。")
        case .zhTW: return PasswordLengthStrings(
            title: "登入密碼長度",
            caption: "管理最小長度規則，不變更密碼。原始規則會儲存在這部 Mac 上，以便還原。",
            shared: "系統層級的長度規則會影響所有本機帳號。",
            minimum: "最少字元數",
            none: "尚未設定可編輯的最小長度規則。請選擇新的最小長度以啟用限制。",
            disable: "移除長度要求…",
            restore: "還原原始要求…",
            enable: "設定最小長度…",
            refresh: "重新整理",
            failed: "無法完成操作。可能已取消授權、政策已變更，或這部 Mac 有受管理或不支援的規則。還原記錄仍會保留。",
            continueAction: "繼續",
            confirm: "需要管理者授權。較短的密碼更容易被猜中。現有密碼不會變更；還原的要求何時生效由 macOS 決定。系統層級的規則會影響所有本機帳號。")
        case .zhHK: return PasswordLengthStrings(
            title: "登入密碼長度",
            caption: "管理最短長度規則，而不更改密碼。原有規則會儲存在此 Mac，以便還原。",
            shared: "系統層級的長度規則會影響所有本機帳户。",
            minimum: "最少字元數",
            none: "未設定可編輯的最短長度規則。請選擇新的最短長度以啟用限制。",
            disable: "移除長度要求…",
            restore: "還原原有要求…",
            enable: "設定最短長度…",
            refresh: "重新整理",
            failed: "無法完成操作。可能已取消授權、政策已更改，或此 Mac 有受管理或不支援的規則。還原記錄仍會保留。",
            continueAction: "繼續",
            confirm: "需要管理員授權。較短的密碼更容易被猜中。現有密碼不會更改；還原的要求何時生效由 macOS 決定。系統層級的規則會影響所有本機帳户。")
        case .ja: return PasswordLengthStrings(
            title: "ログインパスワードの長さ",
            caption: "パスワードを変更せずに最小文字数の規則を管理します。元の規則は復元できるようこのMacに保存されます。",
            shared: "システム全体の文字数規則はすべてのローカルアカウントに適用されます。",
            minimum: "最小文字数",
            none: "編集可能な最小文字数の規則はありません。制限を有効にするには文字数を選んでください。",
            disable: "文字数制限を解除…",
            restore: "元の制限を復元…",
            enable: "最小文字数を設定…",
            refresh: "更新",
            failed: "操作を完了できませんでした。認証のキャンセル、ポリシーの変更、管理対象または未対応の規則が考えられます。復元用の記録は保持されます。",
            continueAction: "続ける",
            confirm: "管理者の認証が必要です。短いパスワードは推測されやすくなります。既存のパスワードは変更されません。復元した規則の適用時期はmacOSが決定します。システム全体の規則はすべてのローカルアカウントに適用されます。")
        case .ko: return PasswordLengthStrings(
            title: "로그인 암호 길이",
            caption: "암호를 변경하지 않고 최소 길이 규칙을 관리합니다. 원래 규칙은 복원을 위해 이 Mac에 저장됩니다.",
            shared: "시스템 전체 길이 규칙은 모든 로컬 계정에 적용됩니다.",
            minimum: "최소 문자 수",
            none: "편집 가능한 최소 길이 규칙이 없습니다. 제한을 활성화하려면 새 최소 길이를 선택하세요.",
            disable: "길이 제한 해제…",
            restore: "원래 제한 복원…",
            enable: "최소 길이 설정…",
            refresh: "새로 고침",
            failed: "작업을 완료하지 못했습니다. 인증이 취소되었거나 정책이 변경되었거나 관리 대상 또는 지원하지 않는 규칙이 있습니다. 복원 기록은 유지됩니다.",
            continueAction: "계속",
            confirm: "관리자 인증이 필요합니다. 짧은 암호는 추측하기 쉽습니다. 기존 암호는 변경되지 않으며 복원된 규칙의 적용 시점은 macOS가 결정합니다. 시스템 전체 규칙은 모든 로컬 계정에 적용됩니다.")
        case .de: return PasswordLengthStrings(
            title: "Länge des Anmeldepassworts",
            caption: "Mindestlängen verwalten, ohne das Passwort zu ändern. Ursprüngliche Regeln werden zur Wiederherstellung auf diesem Mac gespeichert.",
            shared: "Systemweite Längenregeln betreffen alle lokalen Accounts.",
            minimum: "Mindestanzahl an Zeichen",
            none: "Keine bearbeitbare Mindestlänge festgelegt. Wähle eine neue Mindestlänge, um eine Begrenzung zu aktivieren.",
            disable: "Mindestlänge aufheben…",
            restore: "Ursprüngliche Vorgabe wiederherstellen…",
            enable: "Mindestlänge festlegen…",
            refresh: "Aktualisieren",
            failed: "Vorgang nicht abgeschlossen. Die Autorisierung wurde möglicherweise abgebrochen, Regeln wurden geändert oder sind verwaltet bzw. nicht unterstützt. Wiederherstellungsdaten bleiben erhalten.",
            continueAction: "Fortfahren",
            confirm: "Administratorautorisierung erforderlich. Kürzere Passwörter sind leichter zu erraten. Bestehende Passwörter bleiben unverändert; macOS bestimmt, wann wiederhergestellte Vorgaben gelten. Systemweite Regeln betreffen alle lokalen Accounts.")
        case .fr: return PasswordLengthStrings(
            title: "Longueur du mot de passe de session",
            caption: "Gérez la longueur minimale sans changer le mot de passe. Les règles initiales sont conservées sur ce Mac pour être rétablies.",
            shared: "Les règles système concernent tous les comptes locaux.",
            minimum: "Nombre minimal de caractères",
            none: "Aucune règle de longueur minimale modifiable. Choisissez un minimum pour activer une limite.",
            disable: "Supprimer la longueur minimale…",
            restore: "Rétablir les règles initiales…",
            enable: "Définir la longueur minimale…",
            refresh: "Actualiser",
            failed: "Opération impossible : autorisation annulée, règles modifiées, gérées ou non prises en charge. Les données de restauration sont conservées.",
            continueAction: "Continuer",
            confirm: "Une autorisation administrateur est requise. Les mots de passe courts sont plus faciles à deviner. Les mots de passe existants restent inchangés ; macOS détermine quand les règles rétablies s’appliquent. Les règles système concernent tous les comptes locaux.")
        case .es: return PasswordLengthStrings(
            title: "Longitud de la contraseña de inicio",
            caption: "Gestiona la longitud mínima sin cambiar la contraseña. Las reglas originales se guardan en este Mac para restaurarlas.",
            shared: "Las reglas del sistema afectan a todas las cuentas locales.",
            minimum: "Caracteres mínimos",
            none: "No hay una regla editable de longitud mínima. Elige un mínimo para activar un límite.",
            disable: "Quitar requisito de longitud…",
            restore: "Restaurar requisito original…",
            enable: "Establecer longitud mínima…",
            refresh: "Actualizar",
            failed: "No se pudo completar la operación. Es posible que se cancelara la autorización, cambiaran las reglas o sean administradas o incompatibles. Los datos de recuperación se conservan.",
            continueAction: "Continuar",
            confirm: "Se requiere autorización de administrador. Las contraseñas cortas son más fáciles de adivinar. Las contraseñas existentes no cambian; macOS decide cuándo aplicar los requisitos restaurados. Las reglas del sistema afectan a todas las cuentas locales.")
        case .it: return PasswordLengthStrings(
            title: "Lunghezza della password di accesso",
            caption: "Gestisci la lunghezza minima senza cambiare la password. Le regole originali vengono salvate su questo Mac per il ripristino.",
            shared: "Le regole di sistema riguardano tutti gli account locali.",
            minimum: "Numero minimo di caratteri",
            none: "Nessuna regola modificabile sulla lunghezza minima. Scegli un minimo per attivare un limite.",
            disable: "Rimuovi il requisito di lunghezza…",
            restore: "Ripristina il requisito originale…",
            enable: "Imposta la lunghezza minima…",
            refresh: "Aggiorna",
            failed: "Impossibile completare l’operazione. L’autorizzazione potrebbe essere stata annullata, le regole modificate, gestite o non supportate. I dati di ripristino vengono conservati.",
            continueAction: "Continua",
            confirm: "È richiesta l’autorizzazione di un amministratore. Le password brevi sono più facili da indovinare. Le password esistenti non cambiano; macOS decide quando applicare i requisiti ripristinati. Le regole di sistema riguardano tutti gli account locali.")
        case .ptBR: return PasswordLengthStrings(
            title: "Comprimento da senha de login",
            caption: "Gerencie o comprimento mínimo sem alterar a senha. As regras originais são salvas neste Mac para restauração.",
            shared: "Regras do sistema afetam todas as contas locais.",
            minimum: "Mínimo de caracteres",
            none: "Nenhuma regra editável de comprimento mínimo. Escolha um novo mínimo para ativar um limite.",
            disable: "Remover requisito de comprimento…",
            restore: "Restaurar requisito original…",
            enable: "Definir comprimento mínimo…",
            refresh: "Atualizar",
            failed: "Não foi possível concluir a operação. A autorização pode ter sido cancelada, as regras alteradas, gerenciadas ou incompatíveis. Os dados de recuperação são mantidos.",
            continueAction: "Continuar",
            confirm: "É necessária autorização de administrador. Senhas curtas são mais fáceis de adivinhar. As senhas existentes não mudam; o macOS decide quando aplicar os requisitos restaurados. Regras do sistema afetam todas as contas locais.")
        case .ru: return PasswordLengthStrings(
            title: "Длина пароля входа",
            caption: "Управляйте минимальной длиной, не меняя пароль. Исходные правила сохраняются на этом Mac для восстановления.",
            shared: "Общесистемные правила действуют для всех локальных учётных записей.",
            minimum: "Минимум символов",
            none: "Нет доступного для изменения правила длины. Выберите минимум, чтобы включить ограничение.",
            disable: "Убрать требование длины…",
            restore: "Восстановить исходное требование…",
            enable: "Задать минимальную длину…",
            refresh: "Обновить",
            failed: "Не удалось завершить операцию. Возможно, авторизация отменена, правила изменились, управляются организацией или не поддерживаются. Данные восстановления сохранены.",
            continueAction: "Продолжить",
            confirm: "Требуется разрешение администратора. Короткие пароли легче угадать. Существующие пароли не меняются; macOS определяет, когда применить восстановленные требования. Общесистемные правила действуют для всех локальных учётных записей.")
        case .uk: return PasswordLengthStrings(
            title: "Довжина пароля входу",
            caption: "Керуйте мінімальною довжиною, не змінюючи пароль. Початкові правила зберігаються на цьому Mac для відновлення.",
            shared: "Загальносистемні правила діють для всіх локальних облікових записів.",
            minimum: "Мінімум символів",
            none: "Немає доступного для зміни правила довжини. Виберіть мінімум, щоб увімкнути обмеження.",
            disable: "Прибрати вимогу довжини…",
            restore: "Відновити початкову вимогу…",
            enable: "Задати мінімальну довжину…",
            refresh: "Оновити",
            failed: "Не вдалося завершити операцію. Можливо, авторизацію скасовано, правила змінено, ними керує організація або вони не підтримуються. Дані відновлення збережено.",
            continueAction: "Продовжити",
            confirm: "Потрібен дозвіл адміністратора. Короткі паролі легше вгадати. Наявні паролі не змінюються; macOS визначає, коли застосувати відновлені вимоги. Загальносистемні правила діють для всіх локальних облікових записів.")
        case .sk: return PasswordLengthStrings(
            title: "Dĺžka prihlasovacieho hesla",
            caption: "Spravujte minimálnu dĺžku bez zmeny hesla. Pôvodné pravidlá sa uložia na tomto Macu na obnovenie.",
            shared: "Systémové pravidlá platia pre všetky lokálne účty.",
            minimum: "Minimálny počet znakov",
            none: "Nie je nastavené upraviteľné pravidlo dĺžky. Vyberte minimum na zapnutie obmedzenia.",
            disable: "Odstrániť požiadavku na dĺžku…",
            restore: "Obnoviť pôvodnú požiadavku…",
            enable: "Nastaviť minimálnu dĺžku…",
            refresh: "Obnoviť",
            failed: "Operáciu sa nepodarilo dokončiť. Overenie mohlo byť zrušené, pravidlá sa zmenili, sú spravované alebo nepodporované. Údaje na obnovenie sa zachovajú.",
            continueAction: "Pokračovať",
            confirm: "Vyžaduje sa povolenie správcu. Kratšie heslá sa ľahšie uhádnu. Existujúce heslá sa nemenia; macOS určuje, kedy sa obnovené pravidlá použijú. Systémové pravidlá platia pre všetky lokálne účty.")
        case .tr: return PasswordLengthStrings(
            title: "Giriş parolası uzunluğu",
            caption: "Parolayı değiştirmeden en az uzunluk kurallarını yönetin. Özgün kurallar geri yüklemek için bu Mac’te saklanır.",
            shared: "Sistem genelindeki kurallar tüm yerel hesapları etkiler.",
            minimum: "En az karakter sayısı",
            none: "Düzenlenebilir bir uzunluk kuralı yok. Sınırı etkinleştirmek için yeni bir minimum seçin.",
            disable: "Uzunluk gereksinimini kaldır…",
            restore: "Özgün gereksinimi geri yükle…",
            enable: "En az uzunluğu ayarla…",
            refresh: "Yenile",
            failed: "İşlem tamamlanamadı. Yetkilendirme iptal edilmiş, kurallar değişmiş, yönetiliyor veya desteklenmiyor olabilir. Kurtarma verileri saklanır.",
            continueAction: "Devam et",
            confirm: "Yönetici yetkilendirmesi gerekir. Kısa parolalar daha kolay tahmin edilir. Mevcut parolalar değişmez; geri yüklenen kuralların ne zaman uygulanacağına macOS karar verir. Sistem genelindeki kurallar tüm yerel hesapları etkiler.")
        }
    }
}
