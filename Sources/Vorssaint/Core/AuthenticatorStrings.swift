// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the authenticator. Same contract as the other FeatureStrings
/// structs: memberwise init in declaration order, one static per language.
/// English and Russian are complete; the other languages read English until
/// their pass.
struct AuthenticatorFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let paletteTitle: String
    let paletteToggle: String
    let paletteCaption: String
    let searchPlaceholder: String
    let noResults: String
    let emptyList: String
    let emptyPalette: String
    let addButton: String
    let addManually: String
    let scanScreen: String
    let scanHint: String
    let importClipboard: String
    let importFile: String
    let exportFile: String
    let exportQR: String
    let showQR: String
    let newTitle: String
    let editTitle: String
    let issuerLabel: String
    let issuerPlaceholder: String
    let accountLabel: String
    let accountPlaceholder: String
    let secretLabel: String
    let secretPlaceholder: String
    let advancedSection: String
    let kindLabel: String
    let kindTOTP: String
    let kindHOTP: String
    let kindSteam: String
    let algorithmLabel: String
    let digitsLabel: String
    let periodLabel: String
    let counterLabel: String
    let previewLabel: String
    let invalidSecret: String
    let saveButton: String
    let deleteButton: String
    let deleteConfirmFormat: String
    let pinLabel: String
    let copyAction: String
    let typeAction: String
    let nextCodeAction: String
    let copied: String
    let enterAction: String
    let enterTypes: String
    let enterCopies: String
    let typesCaption: String
    let clearsClipboard: String
    let clearsClipboardCaption: String
    let clearDelayFormat: String
    let footerHint: String
    let importTitle: String
    let importFoundFormat: String
    let importDuplicate: String
    let importSkippedFormat: String
    let importAdd: String
    let importNothing: String
    let exportWarningTitle: String
    let exportWarningMessage: String
    let exportContinue: String
    let qrTitle: String
    let qrBatchFormat: String
    let qrScanWithPhone: String
    let keychainErrorFormat: String
    let storeUnreadable: String
    let secretUnavailable: String
    let noCodeFound: String
    let commandBarKind: String
    let manageButton: String
    let settingsSection: String
    let accountsSection: String
    let importMenu: String
    let exportMenu: String
    let listHint: String
    let filterPlaceholder: String
    let moveUp: String
    let moveDown: String
    let scanCamera: String
    let scanCameraHint: String
    let unlockReason: String
    let requiresUnlock: String
    let requiresUnlockCaption: String
    let unlockButton: String
    let lockedCode: String
    let pressesReturn: String
    let pressesReturnCaption: String
    let clockHint: String
    let duplicateWarning: String
    let keyFieldHint: String
    let backupPasswordTitle: String
    let backupCreateMessage: String
    let backupOpenMessage: String
    let passwordPlaceholder: String
    let passwordRepeatPlaceholder: String
    let passwordMismatch: String
    let wrongPassword: String
    let encryptedExportFormat: String
    let exportEncrypted: String
    let exportPlain: String
    let exportPickTitle: String
    let exportSelectAll: String
    let importedFormat: String
    let hotkeyHintFormat: String
    let nextLabel: String
}

extension FeatureStrings {
    static func authenticator(_ language: AppLanguage) -> AuthenticatorFeatureStrings {
        switch language {
        case .ru: return .ru
        case .enUS, .ptBR, .tr, .es, .de, .fr, .it, .ja, .ko, .zhHans, .zhTW, .zhHK: return .enUS
        }
    }
}

extension AuthenticatorFeatureStrings {
    static let enUS = AuthenticatorFeatureStrings(
        pageTitle: "Authenticator",
        hubDescription: "Two-factor codes on the Mac: scan a QR straight off the screen, search, and type the code into any field from a shortcut. Imports and exports what other authenticators speak.",
        panelCaption: "Two-factor codes",
        paletteTitle: "Code palette",
        paletteToggle: "Open the palette with a shortcut",
        paletteCaption: "A floating list of your accounts. Type to search, Return types the code into the app you were in.",
        searchPlaceholder: "Search accounts",
        noResults: "No account matches.",
        emptyList: "No accounts yet. Add one by hand, scan a QR code on the screen, or import from another authenticator.",
        emptyPalette: "No accounts yet.",
        addButton: "Add account",
        addManually: "Enter a key",
        scanScreen: "Scan QR on screen",
        scanHint: "Drag over the QR code shown on the screen.",
        importClipboard: "Import from clipboard",
        importFile: "Import from file…",
        exportFile: "Export to file…",
        exportQR: "Show transfer QR codes",
        showQR: "Show QR code",
        newTitle: "New account",
        editTitle: "Edit account",
        issuerLabel: "Service",
        issuerPlaceholder: "GitHub",
        accountLabel: "Account",
        accountPlaceholder: "name@example.com",
        secretLabel: "Key",
        secretPlaceholder: "Base32 key from the site",
        advancedSection: "Advanced",
        kindLabel: "Type",
        kindTOTP: "Time-based (TOTP)",
        kindHOTP: "Counter-based (HOTP)",
        kindSteam: "Steam Guard",
        algorithmLabel: "Algorithm",
        digitsLabel: "Digits",
        periodLabel: "Period (seconds)",
        counterLabel: "Counter",
        previewLabel: "Current code",
        invalidSecret: "The key must be base32: letters A to Z and digits 2 to 7.",
        saveButton: "Save",
        deleteButton: "Delete",
        deleteConfirmFormat: "Delete %@? The key is removed from the Keychain and cannot be recovered.",
        pinLabel: "Show at the top",
        copyAction: "Copy code",
        typeAction: "Type code",
        nextCodeAction: "Next code",
        copied: "Code copied",
        enterAction: "Return in the palette",
        enterTypes: "Types the code",
        enterCopies: "Copies the code",
        typesCaption: "Typing needs Accessibility. The other action is on ⌘Return either way.",
        clearsClipboard: "Clear the copied code from the clipboard",
        clearsClipboardCaption: "Copied codes are also kept out of Clipboard History.",
        clearDelayFormat: "after %d seconds",
        footerHint: "↩ use · ⌘↩ other action · ⌥↩ next code · ⌘1–9",
        importTitle: "Import accounts",
        importFoundFormat: "%d accounts found",
        importDuplicate: "Already added",
        importSkippedFormat: "%d could not be read",
        importAdd: "Add selected",
        importNothing: "No accounts found in that.",
        exportWarningTitle: "Export keys in plain text?",
        exportWarningMessage: "Anyone with the export can generate your codes. Keep it somewhere private and delete it when the transfer is done.",
        exportContinue: "Export",
        qrTitle: "Transfer to a phone",
        qrBatchFormat: "Code %d of %d",
        qrScanWithPhone: "Scan with Google Authenticator or any app that imports its transfer codes.",
        keychainErrorFormat: "The Keychain refused (error %d).",
        storeUnreadable: "The account list could not be read. Move Authenticator.json out of Application Support to start over.",
        secretUnavailable: "Key unavailable",
        noCodeFound: "No QR code found",
        commandBarKind: "Authenticator · Return copies",
        manageButton: "Manage accounts",
        settingsSection: "Palette",
        accountsSection: "Accounts",
        importMenu: "Import",
        exportMenu: "Export",
        listHint: "Click a code to copy it. Drag the handle to reorder; pinned accounts stay on top in the palette.",
        filterPlaceholder: "Filter",
        moveUp: "Move up",
        moveDown: "Move down",
        scanCamera: "Scan with the camera",
        scanCameraHint: "Hold the phone’s QR code up to the camera.",
        unlockReason: "show your authenticator codes",
        requiresUnlock: "Ask for Touch ID or the password before showing codes",
        requiresUnlockCaption: "Codes stay hidden until you unlock, and hide again after five quiet minutes.",
        unlockButton: "Unlock",
        lockedCode: "Locked",
        pressesReturn: "Press Return after typing a code",
        pressesReturnCaption: "Submits the form straight away. Turn it off if a site needs a click instead.",
        clockHint: "Codes rejected everywhere? Check the Mac’s clock: a time-based code is only right when the time is.",
        duplicateWarning: "An account with this service and name already exists.",
        keyFieldHint: "You can also paste a whole otpauth:// link or a Google transfer link here.",
        backupPasswordTitle: "Backup password",
        backupCreateMessage: "The backup is encrypted with this password. Without it the file cannot be read, and there is no way to recover it.",
        backupOpenMessage: "Enter the password this backup was made with.",
        passwordPlaceholder: "Password",
        passwordRepeatPlaceholder: "Repeat password",
        passwordMismatch: "The two passwords differ. Type the same password twice.",
        wrongPassword: "That is not the backup’s password.",
        encryptedExportFormat: "This %@ file is encrypted. Export it unencrypted in %@ first, or import the accounts one by one from their QR codes.",
        exportEncrypted: "Encrypted backup…",
        exportPlain: "Plain text (otpauth links)…",
        exportPickTitle: "Which accounts?",
        exportSelectAll: "All",
        importedFormat: "%d accounts added",
        hotkeyHintFormat: "The palette opens anywhere with %@.",
        nextLabel: "next"
    )

    static let ru = AuthenticatorFeatureStrings(
        pageTitle: "Аутентификатор",
        hubDescription: "Коды двухфакторной защиты на Маке: скан QR прямо с экрана, поиск, ввод кода в любое поле по шорткату. Импорт и экспорт в форматах других аутентификаторов.",
        panelCaption: "Коды двухфакторной защиты",
        paletteTitle: "Палитра кодов",
        paletteToggle: "Открывать палитру по шорткату",
        paletteCaption: "Плавающий список аккаунтов. Набирайте для поиска, Return печатает код в то приложение, где вы были.",
        searchPlaceholder: "Поиск аккаунтов",
        noResults: "Ничего не найдено.",
        emptyList: "Аккаунтов пока нет. Добавьте вручную, отсканируйте QR с экрана или импортируйте из другого аутентификатора.",
        emptyPalette: "Аккаунтов пока нет.",
        addButton: "Добавить аккаунт",
        addManually: "Ввести ключ",
        scanScreen: "Сканировать QR на экране",
        scanHint: "Выделите QR-код на экране.",
        importClipboard: "Импорт из буфера обмена",
        importFile: "Импорт из файла…",
        exportFile: "Экспорт в файл…",
        exportQR: "Показать QR для переноса",
        showQR: "Показать QR-код",
        newTitle: "Новый аккаунт",
        editTitle: "Правка аккаунта",
        issuerLabel: "Сервис",
        issuerPlaceholder: "GitHub",
        accountLabel: "Аккаунт",
        accountPlaceholder: "name@example.com",
        secretLabel: "Ключ",
        secretPlaceholder: "Ключ base32 с сайта",
        advancedSection: "Дополнительно",
        kindLabel: "Тип",
        kindTOTP: "По времени (TOTP)",
        kindHOTP: "По счётчику (HOTP)",
        kindSteam: "Steam Guard",
        algorithmLabel: "Алгоритм",
        digitsLabel: "Цифр",
        periodLabel: "Период (секунды)",
        counterLabel: "Счётчик",
        previewLabel: "Текущий код",
        invalidSecret: "Ключ должен быть в base32: буквы A–Z и цифры 2–7.",
        saveButton: "Сохранить",
        deleteButton: "Удалить",
        deleteConfirmFormat: "Удалить %@? Ключ будет стёрт из Связки ключей без возможности восстановить.",
        pinLabel: "Показывать сверху",
        copyAction: "Скопировать код",
        typeAction: "Напечатать код",
        nextCodeAction: "Следующий код",
        copied: "Код скопирован",
        enterAction: "Return в палитре",
        enterTypes: "Печатает код",
        enterCopies: "Копирует код",
        typesCaption: "Для печати нужен Универсальный доступ. Второе действие всегда на ⌘Return.",
        clearsClipboard: "Стирать скопированный код из буфера",
        clearsClipboardCaption: "Скопированные коды не попадают в историю буфера.",
        clearDelayFormat: "через %d секунд",
        footerHint: "↩ использовать · ⌘↩ другое действие · ⌥↩ следующий код · ⌘1–9",
        importTitle: "Импорт аккаунтов",
        importFoundFormat: "Найдено аккаунтов: %d",
        importDuplicate: "Уже добавлен",
        importSkippedFormat: "Не удалось прочитать: %d",
        importAdd: "Добавить выбранные",
        importNothing: "Аккаунтов здесь не нашлось.",
        exportWarningTitle: "Экспортировать ключи открытым текстом?",
        exportWarningMessage: "Любой, у кого окажется этот экспорт, сможет генерировать ваши коды. Храните его в надёжном месте и удалите после переноса.",
        exportContinue: "Экспортировать",
        qrTitle: "Перенос на телефон",
        qrBatchFormat: "Код %d из %d",
        qrScanWithPhone: "Отсканируйте в Google Authenticator или любом приложении, которое понимает его коды переноса.",
        keychainErrorFormat: "Связка ключей отказала (ошибка %d).",
        storeUnreadable: "Список аккаунтов не читается. Уберите Authenticator.json из Application Support, чтобы начать заново.",
        secretUnavailable: "Ключ недоступен",
        noCodeFound: "QR-код не найден",
        commandBarKind: "Аутентификатор · Return копирует",
        manageButton: "Управлять аккаунтами",
        settingsSection: "Палитра",
        accountsSection: "Аккаунты",
        importMenu: "Импорт",
        exportMenu: "Экспорт",
        listHint: "Клик по коду копирует его. Тяните за ручку, чтобы поменять порядок; закреплённые аккаунты в палитре идут первыми.",
        filterPlaceholder: "Фильтр",
        moveUp: "Выше",
        moveDown: "Ниже",
        scanCamera: "Сканировать камерой",
        scanCameraHint: "Поднесите QR-код с телефона к камере.",
        unlockReason: "показать коды аутентификатора",
        requiresUnlock: "Спрашивать Touch ID или пароль перед показом кодов",
        requiresUnlockCaption: "Коды скрыты, пока не разблокируете, и прячутся снова через пять минут бездействия.",
        unlockButton: "Разблокировать",
        lockedCode: "Заблокировано",
        pressesReturn: "Нажимать Return после ввода кода",
        pressesReturnCaption: "Форма отправляется сразу. Выключите, если сайту нужен клик по кнопке.",
        clockHint: "Коды нигде не принимают? Проверьте часы Мака: код по времени верен только при верном времени.",
        duplicateWarning: "Аккаунт с таким сервисом и именем уже есть.",
        keyFieldHint: "Сюда можно вставить целиком ссылку otpauth:// или ссылку переноса из Google.",
        backupPasswordTitle: "Пароль резервной копии",
        backupCreateMessage: "Копия шифруется этим паролем. Без него файл не прочитать, восстановить пароль нельзя.",
        backupOpenMessage: "Введите пароль, с которым делали эту копию.",
        passwordPlaceholder: "Пароль",
        passwordRepeatPlaceholder: "Повторите пароль",
        passwordMismatch: "Пароли не совпадают. Введите один и тот же пароль дважды.",
        wrongPassword: "Это не пароль от этой копии.",
        encryptedExportFormat: "Этот файл %@ зашифрован. Сначала сделайте в %@ незашифрованный экспорт или перенесите аккаунты по одному через QR.",
        exportEncrypted: "Зашифрованная копия…",
        exportPlain: "Открытый текст (ссылки otpauth)…",
        exportPickTitle: "Какие аккаунты?",
        exportSelectAll: "Все",
        importedFormat: "Добавлено аккаунтов: %d",
        hotkeyHintFormat: "Палитра открывается где угодно по %@.",
        nextLabel: "след."
    )
}
