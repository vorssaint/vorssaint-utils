// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Languages the interface can use. The first launch defaults to the system
/// language; the onboarding and Settings let the user override it at any time.
enum AppLanguage: String, CaseIterable, Identifiable {
    case enUS = "en-US"
    case ptBR = "pt-BR"
    case es = "es"
    case de = "de"
    case fr = "fr"
    case it = "it"
    case ja = "ja"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    /// The language's own name, shown in its own script, the way macOS lists them.
    var displayName: String {
        switch self {
        case .enUS: return "English (US)"
        case .ptBR: return "Português (Brasil)"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .it: return "Italiano"
        case .ja: return "日本語"
        case .zhHans: return "简体中文"
        }
    }

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let matches: [(String, AppLanguage)] = [
            ("pt", .ptBR), ("es", .es), ("de", .de), ("fr", .fr),
            ("it", .it), ("ja", .ja), ("zh", .zhHans),
        ]
        for (prefix, language) in matches where preferred.hasPrefix(prefix) { return language }
        return .enUS
    }
}

/// Source of every user-facing string. Views observe this object so the whole
/// interface re-renders immediately when the language changes.
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.language) }
    }

    var s: Strings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .zhHans: return .zhHans
        }
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: DefaultsKey.language),
           let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .systemDefault
        }
    }
}

/// Flat, compiler-checked catalog of UI strings. Adding a field here forces
/// both translations to be provided.
struct Strings {
    // MARK: Menu bar & context menu
    let statusIdleTooltip: String
    let statusActiveUntil: String      // + time
    let statusActiveIndefinite: String
    let menuEnableAwake: String
    let menuDisableAwake: String
    let menuActivateFor: String
    let menuSettings: String
    let menuAbout: String
    let menuQuit: String
    // Standard application menu bar (App / Edit / Window) shown while one of the
    // app's own windows is focused. Without it, an accessory app has no main menu
    // and the standard shortcuts (Cmd+H/M/W/Q, Cmd+C/V/X/A) do nothing.
    let menuHide: String
    let menuHideOthers: String
    let menuShowAll: String
    let menuEdit: String
    let menuUndo: String
    let menuRedo: String
    let menuCut: String
    let menuCopy: String
    let menuPaste: String
    let menuSelectAll: String
    let menuWindow: String
    let menuMinimize: String
    let menuZoom: String
    let menuClose: String

    // MARK: Durations
    let minutes15: String
    let minutes30: String
    let hour1: String
    let hours2: String
    let hours4: String
    let hours8: String
    let indefinitely: String
    let indefinite: String

    // MARK: Panel — header & footer
    let panelAwake: String
    let panelNormalSleep: String
    let panelSettings: String
    let panelQuit: String
    let panelHotkeyHint: String

    // MARK: Panel — keep awake card
    let keepAwakeTitle: String
    let keepAwakeEndsIn: String        // + remaining
    let keepAwakeUntilDisabled: String
    let keepAwakeNormalRules: String
    let durationLabel: String
    let clamshellTitle: String
    let clamshellOnCaption: String
    let clamshellNeedsSession: String
    let clamshellReady: String
    let clamshellNeedsPassword: String

    // MARK: Panel — system monitor
    let systemSection: String
    let temperatures: String
    let cpuLabel: String
    let gpuLabel: String
    let batteryLabel: String
    let usageSection: String
    let memorySection: String
    let memoryPressure: String
    let pressureNormal: String
    let pressureWarning: String
    let pressureCritical: String
    let monitorUnavailable: String
    let energyAppsTitle: String
    let energyAppsIdle: String

    // MARK: Notifications
    let notifySessionEndedTitle: String
    let notifySessionEndedBody: String
    let notifyBatteryTitle: String
    let notifyBatteryBody: String

    // MARK: Administrator prompts (shown by macOS password dialogs)
    let adminPromptClamshellOff: String
    let adminPromptRecover: String
    let adminPromptSudoersInstall: String
    let adminPromptSudoersRemove: String

    // MARK: Settings — window & tabs
    let settingsTitle: String
    let tabGeneral: String
    let tabEnergy: String
    let tabMouse: String
    let tabSwitcher: String
    let tabAdvanced: String
    let tabAbout: String
    let tabReleaseNotes: String
    let settingsGroupFeatures: String

    // MARK: Settings — advanced
    let advancedResetSection: String
    let advancedResetDescription: String
    let advancedClearButton: String
    let advancedCleared: String
    let advancedClearConfirmTitle: String
    let advancedClearConfirmBody: String
    let advancedUninstallSection: String
    let advancedUninstallDescription: String
    let advancedUninstallButton: String
    let advancedUninstallConfirmTitle: String
    let advancedUninstallConfirmBody: String

    // MARK: Settings — general
    let launchAtLogin: String
    let languageLabel: String
    let menuBarSection: String
    let showCountdown: String
    let globalHotkeySection: String
    let hotkeyToggle: String
    let hotkeyCaption: String

    // MARK: Settings — energy
    let sessionSection: String
    let defaultDurationLabel: String
    let batteryProtectionSection: String
    let batteryDisableBelow: String
    let batteryNever: String
    let batteryProtectionCaption: String
    let clamshellSection: String
    let configuring: String
    let sudoersFailed: String
    let clamshellExplanation: String

    // MARK: Settings — mouse
    let scrollSection: String
    let invertMouseScroll: String
    let invertMouseScrollCaption: String
    let scrollTrackpadNote: String
    let scrollActiveNow: String

    // MARK: Settings — switcher
    let switcherSection: String
    let switcherEnable: String
    let switcherEnableCaption: String
    let switcherUsageHint: String
    let switcherNoWindows: String
    let switcherMergeTabs: String
    let switcherMergeTabsCaption: String
    let switcherFiltersSection: String
    let switcherCurrentSpaceOnly: String
    let switcherCurrentSpaceOnlyCaption: String
    let switcherCurrentMonitorOnly: String
    let switcherCurrentMonitorOnlyCaption: String
    let switcherHideMinimized: String
    let switcherHideMinimizedCaption: String
    let switcherHideFinder: String
    let switcherHideFinderCaption: String
    let switcherIconsOnly: String
    let switcherIconsOnlyCaption: String

    // MARK: Feature — cut & paste in Finder
    let cutPasteName: String
    let cutPasteEnable: String
    let cutPasteEnableCaption: String
    let cutPasteHowTitle: String
    let cutPasteStep1: String
    let cutPasteStep2: String
    let cutPasteTextNote: String
    let cutPasteActiveNow: String
    let cutPasteAutomationNote: String
    let cutReadyTitle: String
    let cutReadyHint: String
    let cutDoneTitle: String
    let cutMovedSingular: String
    let cutMovedPluralFormat: String      // + count
    let cutSomeFailed: String

    // MARK: Feature — quit on last window close
    let autoQuitName: String
    let autoQuitEnable: String
    let autoQuitEnableCaption: String
    let autoQuitActiveNow: String
    let autoQuitHowTitle: String
    let autoQuitStep1: String
    let autoQuitStep2: String
    let autoQuitPredictableNote: String
    let autoQuitExceptionsTitle: String
    let autoQuitExceptionsCaption: String
    let autoQuitExceptionsEmpty: String
    let autoQuitAddApp: String

    // MARK: Feature — complete app uninstaller
    let uninstallerName: String
    let uninstallerEnableCaption: String
    let uninstallerStep1: String
    let uninstallerStep2: String
    let uninstallerStep3: String
    let uninstallerMenuItem: String
    let uninstallerDropTitle: String
    let uninstallerDropSubtitle: String
    let uninstallerChoose: String
    let uninstallerPickerTitle: String
    let uninstallerPickerSearch: String
    let uninstallerPickerEmpty: String
    let uninstallerEmptyNote: String
    let uninstallerFDANote: String
    let uninstallerFDAGrant: String
    let uninstallerFDAHint: String
    let uninstallerFDARelaunch: String
    let uninstallerScanning: String
    let uninstallerRemoving: String
    let uninstallerFoundTitle: String
    let uninstallerSelectedFormat: String   // + selected, total
    let uninstallerRemove: String
    let uninstallerCancel: String
    let uninstallerDoneTitle: String
    let uninstallerFreedFormat: String      // + size string
    let uninstallerSomeFailed: String
    let uninstallerAnother: String
    let uninstallerCatApp: String
    let uninstallerCatSupport: String
    let uninstallerCatCaches: String
    let uninstallerCatPreferences: String
    let uninstallerCatContainers: String
    let uninstallerCatLogs: String
    let uninstallerCatState: String
    let uninstallerCatOther: String

    // MARK: Feature — URL cleaner
    let urlCleanerName: String
    let urlCleanerEnable: String
    let urlCleanerEnableCaption: String
    let urlCleanerActiveNow: String
    let urlCleanerManualTitle: String
    let urlCleanerInputPlaceholder: String
    let urlCleanerOutputPlaceholder: String
    let urlCleanerCleanButton: String
    let urlCleanerPasteButton: String
    let urlCleanerCopyButton: String
    let urlCleanerClearButton: String
    let urlCleanerNoURL: String
    let urlCleanerNoChange: String
    let urlCleanerCleaned: String
    let urlCleanerCopied: String
    let urlCleanerLocalNote: String

    // MARK: Feature — temporary shelf
    let shelfName: String
    let shelfEnable: String
    let shelfEnableCaption: String
    let shelfHowTitle: String
    let shelfStep1: String
    let shelfStep2: String
    let shelfStep3: String
    let shelfShakeToggle: String
    let shelfShakeCaption: String
    let shelfHotkeyLabel: String
    let shelfOpenNow: String
    let shelfNoPermission: String
    let shelfMenuItem: String
    let shelfTitle: String
    let shelfEmpty: String
    let shelfClearAll: String
    let shelfRemoveSelected: String
    let shelfSelectedFormat: String      // + count
    let shelfHint: String
    let shelfItemImage: String

    // MARK: Panel — per-app breakdown
    let breakdownMeasuring: String

    // MARK: Panel — volume mixer
    let mixerSection: String
    let mixerEmpty: String
    let mixerUnavailable: String
    let mixerPermissionBody: String
    let mixerResetTooltip: String

    // MARK: Settings — updates
    let updatesSection: String
    let autoCheckToggle: String
    let checkNowButton: String
    let updateChecking: String
    let updateUpToDate: String
    let updateAvailablePrefix: String  // + version
    let updateInstallButton: String
    let updateDownloading: String
    let updateInstalling: String
    let updateFailedPrefix: String
    let updateLastChecked: String
    let updateNotifyTitle: String
    let menuCheckUpdates: String

    // MARK: Permissions (shared by Settings & onboarding)
    let permissionRequired: String
    let permissionAccessibility: String
    let permissionScreenRecording: String
    let permissionGranted: String
    let permissionMissing: String
    let permissionOpenSettings: String
    let permissionRequest: String
    let permissionRestartNote: String

    // MARK: About
    let aboutDescription: String
    let versionPrefix: String
    let reviewIntro: String
    let viewOnGitHub: String

    // MARK: Onboarding
    let obContinue: String
    let obBack: String
    let obSkipStep: String
    let obStart: String
    let obStepWelcomeTitle: String
    let obStepWelcomeBody: String
    let obWelcomeBullet1Title: String
    let obWelcomeBullet1Body: String
    let obWelcomeBullet2Title: String
    let obWelcomeBullet2Body: String
    let obWelcomeBullet3Title: String
    let obWelcomeBullet3Body: String
    let obLanguageLabel: String
    let obStepAccessibilityTitle: String
    let obStepAccessibilityBody: String
    let obAccessibilityWhy: String
    let obStepRecordingTitle: String
    let obStepRecordingBody: String
    let obRecordingWhy: String
    let obStepMonitorTitle: String
    let obStepMonitorBody: String
    let obMonitorNoPermission: String
    let obStepOptionalTitle: String
    let obStepOptionalBody: String
    let obStepStatusTitle: String
    let obStepStatusBody: String
    let obStatusRecheck: String
    let obStepDoneTitle: String
    let obStepDoneBody: String
    let obDoneHint: String
    let obWhatsNewTitle: String
    let obWhatsNewFallback: String
    let obLanguageUpdateTitle: String
    let obLanguageUpdateBody: String

    // MARK: Settings — monitor / menu bar metrics
    let tabMonitor: String
    let monitorMenuBarSection: String
    let monitorMenuBarCaption: String
    let monitorShowCPU: String
    let monitorShowMemory: String
    let monitorShowNetwork: String
    let monitorShowPowerLabel: String
    let monitorIntervalLabel: String
    let monitorInterval1: String
    let monitorInterval2: String
    let monitorInterval5: String
    let monitorPanelSection: String
    let panelNavigationMode: String
    let panelNavigationCaption: String
    let panelFooterSections: String
    let panelFooterList: String
    let fanControlBetaShow: String
    let fanControlBetaSection: String
    let fanControlBetaTitle: String
    let fanControlBetaStatus: String
    let fanControlBetaCaption: String
    let fanControlModeAutomatic: String
    let fanControlModeManual: String
    let betaBadge: String

    // MARK: Panel — network
    let networkSection: String
    let networkDownload: String
    let networkUpload: String
    let networkThisSession: String
    let networkMeasuring: String

    // MARK: Panel — power
    let powerSection: String
    let powerSystem: String
    let powerAdapter: String
    let powerBattery: String
    let powerCharging: String
    let powerOnBattery: String
    let powerPluggedIn: String
    let powerUnavailable: String
    let powerAdapterMaxFormat: String   // + rated watts, e.g. "30 W max"
    let monitorShowGPU: String
    let monitorGraphsSection: String
    let monitorGraphsCaption: String

    // MARK: Update notification + onboarding menu bar setup
    let updateBannerTitle: String
    let updateBannerAction: String
    let obStepMenuBarTitle: String
    let obStepMenuBarBody: String
    let obStepMenuBarNote: String
    let monitorLabelStyleLabel: String
    let menuBarLabelStyleCompact: String
    let menuBarLabelStyleClassic: String
    let monitorMemoryStyleLabel: String
    let memoryStyleDot: String
    let memoryStylePercent: String
    let memoryStyleBoth: String

    // MARK: System uptime, battery health, speed test
    let systemUptime: String
    let powerHealth: String
    let powerCycles: String
    let speedTestRun: String
    let speedTestAgain: String
    let speedTestLatency: String
    let speedTestTesting: String
    let speedTestFailed: String

    // MARK: Per-item panel config (Settings + onboarding)
    let monitorShowInPanel: String
    let panelHideItem: String
    let panelShowItem: String
    let panelHiddenItem: String
    let monitorItemUptime: String
    let monitorItemNetSpeed: String
    let monitorItemNetTotals: String
    let monitorItemNetTest: String
    let monitorPanelConfigHint: String
    let monitorOrderSection: String
    let monitorOrderHint: String
    let obStepPanelTitle: String
    let obStepPanelBody: String
    let obStepPanelNavigationTitle: String
    let obStepPanelNavigationBody: String

    // MARK: Cleaning mode
    let cleaningMenuItem: String
    let utilitiesSection: String
    let quickControlsSection: String
    let windowMaximizeName: String
    let windowMaximizeCaption: String
    let windowMaximizeActiveNow: String
    let windowMaximizeNeedsAccessibility: String
    let cleaningPanelCaption: String
    let cleaningOverlayTitle: String
    let cleaningOverlaySubtitle: String
    let cleaningOverlayUnlock: String
    let cleaningOverlayMouseHint: String
    let cleaningNeedsAxTitle: String
    let cleaningNeedsAxBody: String

    // MARK: Support / donate
    let tabSupport: String
    let donateHeading: String
    let donateMessage: String
    let donateButton: String
    let donateThanks: String
    let showMenuBarIcon: String
    let showMenuBarIconCaption: String
}

// MARK: - Português (Brasil)

extension Strings {
    static let ptBR = Strings(
        statusIdleTooltip: "Vorssaint: suspensão normal",
        statusActiveUntil: "Vorssaint: ativo até",
        statusActiveIndefinite: "Vorssaint: ativo indefinidamente",
        menuEnableAwake: "Ativar manter acordado",
        menuDisableAwake: "Desativar manter acordado",
        menuActivateFor: "Ativar por…",
        menuSettings: "Ajustes…",
        menuAbout: "Sobre o Vorssaint",
        menuQuit: "Sair do Vorssaint",
        menuHide: "Ocultar o Vorssaint",
        menuHideOthers: "Ocultar Outros",
        menuShowAll: "Mostrar Tudo",
        menuEdit: "Editar",
        menuUndo: "Desfazer",
        menuRedo: "Refazer",
        menuCut: "Recortar",
        menuCopy: "Copiar",
        menuPaste: "Colar",
        menuSelectAll: "Selecionar Tudo",
        menuWindow: "Janela",
        menuMinimize: "Minimizar",
        menuZoom: "Zoom",
        menuClose: "Fechar",

        minutes15: "15 minutos",
        minutes30: "30 minutos",
        hour1: "1 hora",
        hours2: "2 horas",
        hours4: "4 horas",
        hours8: "8 horas",
        indefinitely: "Indefinidamente",
        indefinite: "Indefinida",

        panelAwake: "Mac acordado",
        panelNormalSleep: "Suspensão normal",
        panelSettings: "Ajustes",
        panelQuit: "Sair",
        panelHotkeyHint: "⌃⌥⌘K alterna",

        keepAwakeTitle: "Manter acordado",
        keepAwakeEndsIn: "Termina em",
        keepAwakeUntilDisabled: "Ativo até você desativar",
        keepAwakeNormalRules: "O Mac segue as regras normais de energia",
        durationLabel: "Duração",
        clamshellTitle: "Continuar com a tampa fechada",
        clamshellOnCaption: "Suspensão totalmente desativada. Atenção à energia",
        clamshellNeedsSession: "Será aplicada sempre que “Manter acordado” estiver ativo",
        clamshellReady: "Pronto. Liga e desliga sem senha",
        clamshellNeedsPassword: "Pedirá a senha de administrador uma vez",

        systemSection: "Sistema",
        temperatures: "Temperaturas",
        cpuLabel: "CPU",
        gpuLabel: "GPU",
        batteryLabel: "Bateria",
        usageSection: "Uso de hardware",
        memorySection: "Memória",
        memoryPressure: "Pressão",
        pressureNormal: "Normal",
        pressureWarning: "Atenção",
        pressureCritical: "Crítico",
        monitorUnavailable: "Sensores indisponíveis neste Mac",
        energyAppsTitle: "Uso significativo de energia",
        energyAppsIdle: "Sem uso significativo de energia",

        notifySessionEndedTitle: "Sessão encerrada",
        notifySessionEndedBody: "O tempo acabou. O Mac voltará a suspender normalmente.",
        notifyBatteryTitle: "Vorssaint desativado",
        notifyBatteryBody: "Bateria baixa. A suspensão normal foi restaurada para proteger a carga.",
        adminPromptClamshellOff: "O Vorssaint precisa da sua senha para reativar a suspensão normal do Mac.",
        adminPromptRecover: "O Vorssaint foi encerrado com a suspensão do Mac desativada. Digite a senha para restaurar a suspensão normal.",
        adminPromptSudoersInstall: "O Vorssaint vai criar uma regra restrita (somente pmset disablesleep) para alternar a tampa fechada sem pedir senha. Esta é a única vez que a senha será necessária.",
        adminPromptSudoersRemove: "O Vorssaint vai remover a regra de tampa fechada sem senha.",

        settingsTitle: "Ajustes do Vorssaint",
        tabGeneral: "Geral",
        tabEnergy: "Energia",
        tabMouse: "Mouse",
        tabSwitcher: "Alternador",
        tabAdvanced: "Avançado",
        tabAbout: "Sobre",
        tabReleaseNotes: "Novidades",
        settingsGroupFeatures: "Recursos",
        advancedResetSection: "Permissões",
        advancedResetDescription: "Remove todas as permissões que você concedeu ao Vorssaint (Acessibilidade, Gravação de Tela, Acesso Total ao Disco e outras), o item de início e a regra de tampa fechada. Útil para começar do zero ou antes de desinstalar. O app continua instalado.",
        advancedClearButton: "Limpar todas as permissões",
        advancedCleared: "Permissões limpas.",
        advancedClearConfirmTitle: "Limpar todas as permissões?",
        advancedClearConfirmBody: "Os recursos que dependem de permissão vão parar de funcionar até você conceder de novo. As suas configurações são mantidas.",
        advancedUninstallSection: "Desinstalar",
        advancedUninstallDescription: "Faz tudo acima e ainda apaga as preferências e move o Vorssaint para a Lixeira, sem deixar rastro no sistema. O app fecha ao final. Você pode reinstalar quando quiser.",
        advancedUninstallButton: "Desinstalar o Vorssaint completamente",
        advancedUninstallConfirmTitle: "Desinstalar o Vorssaint?",
        advancedUninstallConfirmBody: "O Vorssaint vai limpar as permissões, apagar as preferências e ir para a Lixeira, e então fechar. Esta ação não pode ser desfeita pelo app, mas ele fica na Lixeira até você esvaziá-la.",

        launchAtLogin: "Iniciar junto com o Mac",
        languageLabel: "Idioma",
        menuBarSection: "Barra de menus",
        showCountdown: "Mostrar tempo restante ao lado do ícone",
        globalHotkeySection: "Atalho global",
        hotkeyToggle: "Alternar “Manter acordado” com ⌃⌥⌘K",
        hotkeyCaption: "Funciona em qualquer app, sem permissões extras.",

        sessionSection: "Sessão",
        defaultDurationLabel: "Duração padrão",
        batteryProtectionSection: "Proteção de bateria",
        batteryDisableBelow: "Desativar com bateria abaixo de",
        batteryNever: "Nunca",
        batteryProtectionCaption: "Evita que uma sessão esquecida drene a bateria do MacBook.",
        clamshellSection: "Tampa fechada",
        configuring: "Configurando…",
        sudoersFailed: "Não foi possível concluir. Verifique a senha e tente de novo.",
        clamshellExplanation: "“Continuar com a tampa fechada” desativa completamente a suspensão enquanto “Manter acordado” estiver ativo e é revertido automaticamente quando a sessão termina ou o app é encerrado. Prefira usá-lo conectado à energia.",

        scrollSection: "Rolagem",
        invertMouseScroll: "Inverter rolagem do mouse",
        invertMouseScrollCaption: "Inverte a direção da roda do mouse.",
        scrollTrackpadNote: "O trackpad não muda: continua com a rolagem natural do macOS.",
        scrollActiveNow: "Invertendo a rolagem do mouse agora",

        switcherSection: "Alternador de apps",
        switcherEnable: "Substituir o ⌘Tab pelo alternador do Vorssaint",
        switcherEnableCaption: "Troque de janela vendo miniaturas reais, inclusive entre várias janelas do mesmo app.",
        switcherUsageHint: "Segure ⌘ e toque Tab para navegar; solte para ativar a janela. Shift ou ← volta; Q fecha o app selecionado; Esc cancela.",
        switcherNoWindows: "Nenhuma janela aberta",
        switcherMergeTabs: "Mostrar uma entrada por app",
        switcherMergeTabsCaption: "Junta todas as janelas de um app em uma só entrada no alternador, em vez de uma por janela.",
        switcherFiltersSection: "Filtros",
        switcherCurrentSpaceOnly: "Mostrar apenas janelas do Espaço atual",
        switcherCurrentSpaceOnlyCaption: "Oculta janelas de outros Espaços. Janelas minimizadas também não são exibidas com esta opção ativa.",
        switcherCurrentMonitorOnly: "Mostrar apenas janelas do monitor atual",
        switcherCurrentMonitorOnlyCaption: "Limita o alternador às janelas cujo quadro está no mesmo monitor que o cursor.",
        switcherHideMinimized: "Ocultar janelas minimizadas",
        switcherHideMinimizedCaption: "Remove janelas minimizadas do alternador. Requer Acessibilidade.",
        switcherHideFinder: "Ocultar o Finder",
        switcherHideFinderCaption: "Remove o Finder do alternador, inclusive quando não há janelas abertas.",
        switcherIconsOnly: "Mostrar apenas ícones dos apps, sem miniaturas ao vivo",
        switcherIconsOnlyCaption: "Desativa o uso de Gravação de Tela pelo alternador. Cada card exibe o ícone do app em vez de uma captura ao vivo.",

        cutPasteName: "Recortar e colar",
        cutPasteEnable: "Recortar e colar arquivos no Finder",
        cutPasteEnableCaption: "Use ⌘X para recortar e ⌘V para mover arquivos e pastas no Finder.",
        cutPasteHowTitle: "Como usar",
        cutPasteStep1: "Selecione itens no Finder e pressione ⌘X para recortá-los.",
        cutPasteStep2: "Abra a pasta de destino e pressione ⌘V para movê-los para lá.",
        cutPasteTextNote: "Em campos de texto (como ao renomear), ⌘X e ⌘V continuam funcionando normalmente.",
        cutPasteActiveNow: "Pronto para recortar no Finder",
        cutPasteAutomationNote: "Na primeira vez, o macOS pede permissão para controlar o Finder.",
        cutReadyTitle: "Recortado",
        cutReadyHint: "na pasta de destino para mover",
        cutDoneTitle: "Movido!",
        cutMovedSingular: "1 item movido",
        cutMovedPluralFormat: "%d itens movidos",
        cutSomeFailed: "Alguns itens não puderam ser movidos",

        autoQuitName: "Encerrar ao fechar",
        autoQuitEnable: "Encerrar o app ao fechar a última janela",
        autoQuitEnableCaption: "Fechar a última janela de um app também o encerra.",
        autoQuitActiveNow: "Ativo e monitorando janelas",
        autoQuitHowTitle: "Como funciona",
        autoQuitStep1: "Feche a última janela de um app (⌘W ou o botão vermelho).",
        autoQuitStep2: "O app é encerrado sozinho. Diálogos de “salvar?” continuam aparecendo.",
        autoQuitPredictableNote: "Apps que normalmente rodam sem janela nunca são encerrados.",
        autoQuitExceptionsTitle: "Exceções",
        autoQuitExceptionsCaption: "Apps nesta lista continuam abertos mesmo sem nenhuma janela.",
        autoQuitExceptionsEmpty: "Nenhuma exceção",
        autoQuitAddApp: "Adicionar app…",

        uninstallerName: "Desinstalador",
        uninstallerEnableCaption: "Remove um app junto com os caches, preferências, logs e resíduos que ele deixa para trás.",
        uninstallerStep1: "Arraste um app para os Ajustes ou escolha um da lista.",
        uninstallerStep2: "Revise os arquivos encontrados e quanto espaço ocupam.",
        uninstallerStep3: "Mova o que quiser para a Lixeira. Nada é apagado de forma definitiva.",
        uninstallerMenuItem: "Desinstalar um app…",
        uninstallerDropTitle: "Arraste um app aqui",
        uninstallerDropSubtitle: "ou escolha um para analisar",
        uninstallerChoose: "Escolher app…",
        uninstallerPickerTitle: "Escolher app",
        uninstallerPickerSearch: "Buscar apps",
        uninstallerPickerEmpty: "Nenhum app encontrado",
        uninstallerEmptyNote: "Nada é removido sem a sua confirmação.",
        uninstallerFDANote: "Conceda Acesso Total ao Disco para uma análise mais completa.",
        uninstallerFDAGrant: "Conceder acesso…",
        uninstallerFDAHint: "Ative o Vorssaint na lista. Se ele não aparecer, clique no + e escolha o Vorssaint em Aplicativos. O acesso só vale depois de reabrir o app.",
        uninstallerFDARelaunch: "Reabrir agora",
        uninstallerScanning: "Analisando arquivos…",
        uninstallerRemoving: "Movendo para a Lixeira…",
        uninstallerFoundTitle: "encontrado",
        uninstallerSelectedFormat: "%d de %d selecionados",
        uninstallerRemove: "Mover para a Lixeira",
        uninstallerCancel: "Cancelar",
        uninstallerDoneTitle: "Pronto!",
        uninstallerFreedFormat: "%@ recuperados",
        uninstallerSomeFailed: "Alguns itens não puderam ser movidos para a Lixeira.",
        uninstallerAnother: "Desinstalar outro",
        uninstallerCatApp: "Aplicativo",
        uninstallerCatSupport: "Suporte",
        uninstallerCatCaches: "Caches",
        uninstallerCatPreferences: "Preferências",
        uninstallerCatContainers: "Contêineres",
        uninstallerCatLogs: "Logs",
        uninstallerCatState: "Estado salvo",
        uninstallerCatOther: "Outros",

        urlCleanerName: "Limpar URL",
        urlCleanerEnable: "Limpar URLs copiadas",
        urlCleanerEnableCaption: "Remove parâmetros de rastreamento de links copiados.",
        urlCleanerActiveNow: "Ativo e observando a área de transferência",
        urlCleanerManualTitle: "Limpar agora",
        urlCleanerInputPlaceholder: "Cole uma URL",
        urlCleanerOutputPlaceholder: "A URL limpa aparece aqui",
        urlCleanerCleanButton: "Limpar",
        urlCleanerPasteButton: "Colar",
        urlCleanerCopyButton: "Copiar",
        urlCleanerClearButton: "Limpar campo",
        urlCleanerNoURL: "Cole uma URL válida.",
        urlCleanerNoChange: "Nada para limpar.",
        urlCleanerCleaned: "URL limpa.",
        urlCleanerCopied: "Copiado.",
        urlCleanerLocalNote: "Local. Sem rede.",

        shelfName: "Área temporária",
        shelfEnable: "Área temporária para arrastar arquivos",
        shelfEnableCaption: "Um espaço flutuante para juntar arquivos, imagens e textos e arrastá-los depois para qualquer app.",
        shelfHowTitle: "Como usar",
        shelfStep1: "Abra a área com ⌃⌥⌘D ou sacudindo o mouse durante um arraste.",
        shelfStep2: "Solte arquivos, imagens, links ou texto sobre ela para guardá-los.",
        shelfStep3: "Arraste cada item de volta para qualquer app quando precisar.",
        shelfShakeToggle: "Abrir sacudindo o mouse durante o arraste",
        shelfShakeCaption: "Sacuda o ponteiro rapidamente segurando um item para chamar a área perto do cursor.",
        shelfHotkeyLabel: "Atalho",
        shelfOpenNow: "Abrir agora",
        shelfNoPermission: "Não requer nenhuma permissão.",
        shelfMenuItem: "Abrir área temporária",
        shelfTitle: "Área temporária",
        shelfEmpty: "Arraste itens aqui",
        shelfClearAll: "Limpar tudo",
        shelfRemoveSelected: "Remover selecionados",
        shelfSelectedFormat: "%d selecionados",
        shelfHint: "Clique para selecionar. Arraste para fora para usar.",
        shelfItemImage: "Imagem",

        breakdownMeasuring: "Medindo…",

        mixerSection: "Mixer de volume",
        mixerEmpty: "Apps que usam áudio aparecem aqui",
        mixerUnavailable: "Disponível a partir do macOS 14.4",
        mixerPermissionBody: "Para ajustar o volume por app, permita “Gravação de Tela e Áudio do Sistema” nos Ajustes do Sistema. O áudio nunca é gravado.",
        mixerResetTooltip: "Voltar para 100%",

        updatesSection: "Atualizações",
        autoCheckToggle: "Procurar atualizações automaticamente",
        checkNowButton: "Procurar agora",
        updateChecking: "Procurando…",
        updateUpToDate: "Você está na versão mais recente.",
        updateAvailablePrefix: "Atualização disponível:",
        updateInstallButton: "Baixar e instalar",
        updateDownloading: "Baixando atualização…",
        updateInstalling: "Instalando e reiniciando…",
        updateFailedPrefix: "Não foi possível verificar:",
        updateLastChecked: "Última verificação:",
        updateNotifyTitle: "Atualização do Vorssaint",
        menuCheckUpdates: "Procurar atualizações…",

        permissionRequired: "Permissão necessária",
        permissionAccessibility: "Acessibilidade",
        permissionScreenRecording: "Gravação de Tela",
        permissionGranted: "Concedida",
        permissionMissing: "Não concedida",
        permissionOpenSettings: "Abrir Ajustes do Sistema…",
        permissionRequest: "Conceder acesso",
        permissionRestartNote: "O macOS pode pedir para reabrir o app depois de conceder.",

        aboutDescription: "Central de utilidades para o seu Mac.\nEnergia, monitor do sistema, rolagem e alternador de janelas, direto na barra de menus.",
        versionPrefix: "Versão",
        reviewIntro: "Rever introdução",
        viewOnGitHub: "Ver no GitHub",

        obContinue: "Continuar",
        obBack: "Voltar",
        obSkipStep: "Pular esta etapa",
        obStart: "Abrir o Vorssaint",
        obStepWelcomeTitle: "Bem-vindo ao Vorssaint",
        obStepWelcomeBody: "Um utilitário discreto na barra de menus que deixa o macOS mais prático no dia a dia.",
        obWelcomeBullet1Title: "Energia sob controle",
        obWelcomeBullet1Body: "Mantenha o Mac acordado por quanto tempo quiser, até com a tampa fechada.",
        obWelcomeBullet2Title: "Visão clara do sistema",
        obWelcomeBullet2Body: "Temperaturas, uso de CPU e GPU e pressão de memória em tempo real.",
        obWelcomeBullet3Title: "Mouse e janelas do seu jeito",
        obWelcomeBullet3Body: "Rolagem invertida no mouse e um alternador de janelas com miniaturas.",
        obLanguageLabel: "Idioma",
        obStepAccessibilityTitle: "Acessibilidade",
        obStepAccessibilityBody: "Necessária para inverter a rolagem do mouse e para o alternador de janelas responder ao teclado.",
        obAccessibilityWhy: "O app só observa a roda do mouse e o atalho do alternador. Nada é gravado nem enviado a lugar algum.",
        obStepRecordingTitle: "Gravação de Tela",
        obStepRecordingBody: "Permite mostrar miniaturas reais das janelas no alternador, em vez de apenas ícones.",
        obRecordingWhy: "As miniaturas são geradas na hora, ficam só na memória e nunca saem do seu Mac. Sem ela, o alternador funciona com ícones.",
        obStepMonitorTitle: "Monitor do sistema",
        obStepMonitorBody: "O painel mostra as temperaturas de CPU, GPU e bateria, o uso de hardware e a pressão de memória.",
        obMonitorNoPermission: "Não precisa de permissão. Os sensores são lidos direto do sistema.",
        obStepOptionalTitle: "Recursos opcionais",
        obStepOptionalBody: "Ative agora o que quiser usar. Tudo pode ser mudado depois nos Ajustes.",
        obStepStatusTitle: "Verificação",
        obStepStatusBody: "Confira se está tudo pronto para os recursos que você quer usar.",
        obStatusRecheck: "Verificar novamente",
        obStepDoneTitle: "Tudo pronto!",
        obStepDoneBody: "O Vorssaint já está cuidando do seu Mac.",
        obDoneHint: "Procure o buraco negro na barra de menus, no canto superior direito da tela.",
        obWhatsNewTitle: "Novidades nesta versão",
        obWhatsNewFallback: "Esta atualização inclui as correções e melhorias mais recentes.",
        obLanguageUpdateTitle: "Agora no seu idioma",
        obLanguageUpdateBody: "O Vorssaint agora fala vários idiomas. Escolha o que você prefere usar; dá para mudar quando quiser nos Ajustes.",

        tabMonitor: "Monitor",
        monitorMenuBarSection: "Na barra de menus",
        monitorMenuBarCaption: "Escolha o que aparece ao lado do ícone na barra de menus.",
        monitorShowCPU: "CPU",
        monitorShowMemory: "Memória",
        monitorShowNetwork: "Rede",
        monitorShowPowerLabel: "Energia",
        monitorIntervalLabel: "Atualizar a cada",
        monitorInterval1: "1 segundo",
        monitorInterval2: "2 segundos",
        monitorInterval5: "5 segundos",
        monitorPanelSection: "No painel",
        panelNavigationMode: "Navegar por seções no painel",
        panelNavigationCaption: "Mostra uma seção por vez e coloca a navegação na parte de baixo do painel.",
        panelFooterSections: "Seções",
        panelFooterList: "Lista",
        fanControlBetaShow: "Mostrar Fan Control (Beta) no painel",
        fanControlBetaSection: "Fan Control",
        fanControlBetaTitle: "Fan Control",
        fanControlBetaStatus: "Automático",
        fanControlBetaCaption: "Beta. O controle manual fica desativado até validação por modelo de Mac.",
        fanControlModeAutomatic: "Automático",
        fanControlModeManual: "Manual",
        betaBadge: "BETA",

        networkSection: "Rede",
        networkDownload: "Download",
        networkUpload: "Upload",
        networkThisSession: "Nesta sessão",
        networkMeasuring: "Medindo…",

        powerSection: "Energia",
        powerSystem: "Sistema",
        powerAdapter: "Adaptador",
        powerBattery: "Bateria",
        powerCharging: "Carregando",
        powerOnBattery: "Na bateria",
        powerPluggedIn: "Na tomada",
        powerUnavailable: "Métricas de energia indisponíveis neste Mac",
        powerAdapterMaxFormat: "%@ máx.",
        monitorShowGPU: "GPU",
        monitorGraphsSection: "Gráficos",
        monitorGraphsCaption: "Escolha quais métricas mostram um gráfico ao longo do tempo.",

        updateBannerTitle: "Atualização disponível",
        updateBannerAction: "Atualizar",
        obStepMenuBarTitle: "Métricas na barra de menus",
        obStepMenuBarBody: "Escolha o que mostrar ao lado do ícone. A prévia acima muda em tempo real.",
        obStepMenuBarNote: "Novidade: blocos de Rede e Energia e gráficos no painel. Ajuste tudo depois em Ajustes › Monitor.",
        monitorLabelStyleLabel: "Rótulos",
        menuBarLabelStyleCompact: "Compactos",
        menuBarLabelStyleClassic: "Clássicos",
        monitorMemoryStyleLabel: "Mostrar memória como",
        memoryStyleDot: "Ponto",
        memoryStylePercent: "%",
        memoryStyleBoth: "Ambos",

        systemUptime: "Ativo há",
        powerHealth: "Saúde da bateria",
        powerCycles: "ciclos",
        speedTestRun: "Testar velocidade",
        speedTestAgain: "Testar de novo",
        speedTestLatency: "Latência",
        speedTestTesting: "Testando…",
        speedTestFailed: "Falha no teste",

        monitorShowInPanel: "Mostrar no painel",
        panelHideItem: "Ocultar do painel",
        panelShowItem: "Mostrar no painel",
        panelHiddenItem: "Oculto",
        monitorItemUptime: "Tempo ativo",
        monitorItemNetSpeed: "Velocidade ao vivo",
        monitorItemNetTotals: "Totais da sessão",
        monitorItemNetTest: "Teste de velocidade",
        monitorPanelConfigHint: "Abra um bloco para escolher o que ele mostra.",
        monitorOrderSection: "Ordem das seções",
        monitorOrderHint: "Arraste para reordenar as seções do painel. Use o chevron de cada seção no painel para recolher.",
        obStepPanelTitle: "O que aparece no painel",
        obStepPanelBody: "Abra cada bloco e escolha exatamente o que mostrar quando você clica no ícone.",
        obStepPanelNavigationTitle: "Painel por seções",
        obStepPanelNavigationBody: "O painel agora pode mostrar uma seção por vez, com a navegação na parte de baixo. A opção vem ligada nesta atualização para você testar.",

        cleaningMenuItem: "Modo de limpeza",
        utilitiesSection: "Utilidades",
        quickControlsSection: "Controles",
        windowMaximizeName: "Maximizar janelas",
        windowMaximizeCaption: "O botão verde maximiza sem criar outro Espaço.",
        windowMaximizeActiveNow: "Ativo no botão verde",
        windowMaximizeNeedsAccessibility: "Precisa de Acessibilidade para funcionar.",
        cleaningPanelCaption: "Bloqueia o teclado para limpar com segurança.",
        cleaningOverlayTitle: "Teclado bloqueado para limpeza",
        cleaningOverlaySubtitle: "Pressione a mesma tecla 5 vezes para desbloquear",
        cleaningOverlayUnlock: "Desbloquear",
        cleaningOverlayMouseHint: "O mouse e o trackpad continuam funcionando",
        cleaningNeedsAxTitle: "Precisa de Acessibilidade",
        cleaningNeedsAxBody: "Para bloquear o teclado com segurança, o Vorssaint precisa da permissão de Acessibilidade. Conceda em Ajustes do Sistema e tente de novo.",

        tabSupport: "Apoiar",
        donateHeading: "Apoie o Vorssaint",
        donateMessage: "Todos os meus projetos públicos são, e sempre serão, totalmente gratuitos: sem assinatura, sem anúncios. O apoio da comunidade é a única forma de manter tudo vivo. Se o Vorssaint te ajuda, um café faz diferença de verdade.",
        donateButton: "Buy me a coffee",
        donateThanks: "Obrigado por estar aqui. 🖤",
        showMenuBarIcon: "Mostrar ícone na barra de menus",
        showMenuBarIconCaption: "Se o ícone do Vorssaint sumir (o macOS pode esconder ícones quando a barra de menus fica sem espaço, comum em Macs com notch), reabra o Vorssaint pela pasta Aplicativos ou pelo Spotlight: isso recria o ícone e, se ele ainda estiver escondido, abre esta janela. O botão acima faz o mesmo quando você já consegue chegar aqui. Manter menos ícones na barra, ou menos métricas no Vorssaint, reduz bastante a chance."
    )
}

// MARK: - English (US)

extension Strings {
    static let enUS = Strings(
        statusIdleTooltip: "Vorssaint: normal sleep",
        statusActiveUntil: "Vorssaint: awake until",
        statusActiveIndefinite: "Vorssaint: awake indefinitely",
        menuEnableAwake: "Enable keep awake",
        menuDisableAwake: "Disable keep awake",
        menuActivateFor: "Activate for…",
        menuSettings: "Settings…",
        menuAbout: "About Vorssaint",
        menuQuit: "Quit Vorssaint",
        menuHide: "Hide Vorssaint",
        menuHideOthers: "Hide Others",
        menuShowAll: "Show All",
        menuEdit: "Edit",
        menuUndo: "Undo",
        menuRedo: "Redo",
        menuCut: "Cut",
        menuCopy: "Copy",
        menuPaste: "Paste",
        menuSelectAll: "Select All",
        menuWindow: "Window",
        menuMinimize: "Minimize",
        menuZoom: "Zoom",
        menuClose: "Close",

        minutes15: "15 minutes",
        minutes30: "30 minutes",
        hour1: "1 hour",
        hours2: "2 hours",
        hours4: "4 hours",
        hours8: "8 hours",
        indefinitely: "Indefinitely",
        indefinite: "Indefinite",

        panelAwake: "Mac awake",
        panelNormalSleep: "Normal sleep",
        panelSettings: "Settings",
        panelQuit: "Quit",
        panelHotkeyHint: "⌃⌥⌘K toggles",

        keepAwakeTitle: "Keep awake",
        keepAwakeEndsIn: "Ends in",
        keepAwakeUntilDisabled: "Active until you turn it off",
        keepAwakeNormalRules: "The Mac follows its normal energy rules",
        durationLabel: "Duration",
        clamshellTitle: "Keep going with the lid closed",
        clamshellOnCaption: "Sleep fully disabled. Mind the power",
        clamshellNeedsSession: "Applied whenever “Keep awake” is active",
        clamshellReady: "Ready. Toggles without a password",
        clamshellNeedsPassword: "Will ask for the administrator password once",

        systemSection: "System",
        temperatures: "Temperatures",
        cpuLabel: "CPU",
        gpuLabel: "GPU",
        batteryLabel: "Battery",
        usageSection: "Hardware usage",
        memorySection: "Memory",
        memoryPressure: "Pressure",
        pressureNormal: "Normal",
        pressureWarning: "Caution",
        pressureCritical: "Critical",
        monitorUnavailable: "Sensors unavailable on this Mac",
        energyAppsTitle: "Apps using significant energy",
        energyAppsIdle: "No significant energy use",

        notifySessionEndedTitle: "Session ended",
        notifySessionEndedBody: "Time is up. The Mac will sleep normally again.",
        notifyBatteryTitle: "Vorssaint disabled",
        notifyBatteryBody: "Low battery. Normal sleep was restored to protect the charge.",
        adminPromptClamshellOff: "Vorssaint needs your password to restore the Mac's normal sleep.",
        adminPromptRecover: "Vorssaint quit while the Mac's sleep was disabled. Enter the password to restore normal sleep.",
        adminPromptSudoersInstall: "Vorssaint will create a restricted rule (pmset disablesleep only) to toggle closed-lid mode without asking for a password. This is the only time the password is needed.",
        adminPromptSudoersRemove: "Vorssaint will remove the password-free closed-lid rule.",

        settingsTitle: "Vorssaint Settings",
        tabGeneral: "General",
        tabEnergy: "Energy",
        tabMouse: "Mouse",
        tabSwitcher: "Switcher",
        tabAdvanced: "Advanced",
        tabAbout: "About",
        tabReleaseNotes: "What's New",
        settingsGroupFeatures: "Features",
        advancedResetSection: "Permissions",
        advancedResetDescription: "Removes every permission you granted Vorssaint (Accessibility, Screen Recording, Full Disk Access and others), the login item and the closed-lid rule. Useful to start fresh or before uninstalling. The app stays installed.",
        advancedClearButton: "Clear all permissions",
        advancedCleared: "Permissions cleared.",
        advancedClearConfirmTitle: "Clear all permissions?",
        advancedClearConfirmBody: "Features that need permissions will stop working until you grant them again. Your settings are kept.",
        advancedUninstallSection: "Uninstall",
        advancedUninstallDescription: "Does all of the above, then removes the preferences and moves Vorssaint to the Trash, leaving nothing behind. The app quits when done. You can reinstall anytime.",
        advancedUninstallButton: "Uninstall Vorssaint completely",
        advancedUninstallConfirmTitle: "Uninstall Vorssaint?",
        advancedUninstallConfirmBody: "Vorssaint will clear its permissions, remove its preferences and move to the Trash, then quit. This can't be undone from the app, but it stays in the Trash until you empty it.",

        launchAtLogin: "Launch at login",
        languageLabel: "Language",
        menuBarSection: "Menu bar",
        showCountdown: "Show remaining time next to the icon",
        globalHotkeySection: "Global shortcut",
        hotkeyToggle: "Toggle “Keep awake” with ⌃⌥⌘K",
        hotkeyCaption: "Works in any app, no extra permissions.",

        sessionSection: "Session",
        defaultDurationLabel: "Default duration",
        batteryProtectionSection: "Battery protection",
        batteryDisableBelow: "Disable when battery drops below",
        batteryNever: "Never",
        batteryProtectionCaption: "Keeps a forgotten session from draining the MacBook battery.",
        clamshellSection: "Closed lid",
        configuring: "Configuring…",
        sudoersFailed: "Could not finish. Check the password and try again.",
        clamshellExplanation: "“Keep going with the lid closed” fully disables sleep while “Keep awake” is active and is reverted automatically when the session ends or the app quits. Prefer using it plugged in.",

        scrollSection: "Scrolling",
        invertMouseScroll: "Invert mouse scrolling",
        invertMouseScrollCaption: "Reverses the mouse wheel direction.",
        scrollTrackpadNote: "The trackpad is untouched: it keeps macOS natural scrolling.",
        scrollActiveNow: "Inverting mouse scrolling right now",

        switcherSection: "App switcher",
        switcherEnable: "Replace ⌘Tab with the Vorssaint switcher",
        switcherEnableCaption: "Switch windows with real thumbnails, including between multiple windows of the same app.",
        switcherUsageHint: "Hold ⌘ and tap Tab to navigate; release to activate the window. Shift or ← goes back; Q quits the selected app; Esc cancels.",
        switcherNoWindows: "No open windows",
        switcherMergeTabs: "Show one entry per app",
        switcherMergeTabsCaption: "Collapses all of an app's windows into one entry in the switcher, instead of one entry per window.",
        switcherFiltersSection: "Filters",
        switcherCurrentSpaceOnly: "Only show windows from the current desktop",
        switcherCurrentSpaceOnlyCaption: "Hides windows on other Spaces. Minimized windows are not shown when this is on.",
        switcherCurrentMonitorOnly: "Only show windows from the current monitor",
        switcherCurrentMonitorOnlyCaption: "Limits the switcher to windows whose frame is on the same display as the cursor.",
        switcherHideMinimized: "Hide minimized windows",
        switcherHideMinimizedCaption: "Removes minimized windows from the switcher. Requires Accessibility.",
        switcherHideFinder: "Hide Finder",
        switcherHideFinderCaption: "Removes Finder from the switcher, including when Finder has no open windows.",
        switcherIconsOnly: "Show app icons only, no live thumbnails",
        switcherIconsOnlyCaption: "Disables Screen Recording use by the switcher. Each card shows the app icon instead of a live window capture.",

        cutPasteName: "Cut & paste",
        cutPasteEnable: "Cut & paste files in Finder",
        cutPasteEnableCaption: "Use ⌘X to cut and ⌘V to move files and folders in Finder.",
        cutPasteHowTitle: "How to use",
        cutPasteStep1: "Select items in Finder and press ⌘X to cut them.",
        cutPasteStep2: "Open the destination folder and press ⌘V to move them there.",
        cutPasteTextNote: "In text fields (like when renaming), ⌘X and ⌘V keep working as usual.",
        cutPasteActiveNow: "Ready to cut in Finder",
        cutPasteAutomationNote: "The first time, macOS asks for permission to control Finder.",
        cutReadyTitle: "Cut",
        cutReadyHint: "in the destination folder to move",
        cutDoneTitle: "Moved!",
        cutMovedSingular: "1 item moved",
        cutMovedPluralFormat: "%d items moved",
        cutSomeFailed: "Some items couldn’t be moved",

        autoQuitName: "Quit on close",
        autoQuitEnable: "Quit an app when its last window closes",
        autoQuitEnableCaption: "Closing an app's last window also quits it.",
        autoQuitActiveNow: "Active and watching windows",
        autoQuitHowTitle: "How it works",
        autoQuitStep1: "Close an app's last window (⌘W or the red button).",
        autoQuitStep2: "The app quits on its own. “Save changes?” dialogs still appear.",
        autoQuitPredictableNote: "Apps that normally run without a window are never quit.",
        autoQuitExceptionsTitle: "Exceptions",
        autoQuitExceptionsCaption: "Apps on this list stay open even with no windows.",
        autoQuitExceptionsEmpty: "No exceptions",
        autoQuitAddApp: "Add app…",

        uninstallerName: "Uninstaller",
        uninstallerEnableCaption: "Removes an app together with the caches, preferences, logs and leftovers it leaves behind.",
        uninstallerStep1: "Drag an app onto Settings, or pick one from the list.",
        uninstallerStep2: "Review the files found and how much space they take.",
        uninstallerStep3: "Move what you want to the Trash. Nothing is deleted permanently.",
        uninstallerMenuItem: "Uninstall an app…",
        uninstallerDropTitle: "Drag an app here",
        uninstallerDropSubtitle: "or choose one to scan",
        uninstallerChoose: "Choose app…",
        uninstallerPickerTitle: "Choose app",
        uninstallerPickerSearch: "Search apps",
        uninstallerPickerEmpty: "No apps found",
        uninstallerEmptyNote: "Nothing is removed without your confirmation.",
        uninstallerFDANote: "Grant Full Disk Access for a more thorough scan.",
        uninstallerFDAGrant: "Grant access…",
        uninstallerFDAHint: "Turn Vorssaint on in the list. If it isn't there, click + and pick Vorssaint from Applications. Access only applies after you reopen the app.",
        uninstallerFDARelaunch: "Relaunch now",
        uninstallerScanning: "Scanning files…",
        uninstallerRemoving: "Moving to the Trash…",
        uninstallerFoundTitle: "found",
        uninstallerSelectedFormat: "%d of %d selected",
        uninstallerRemove: "Move to Trash",
        uninstallerCancel: "Cancel",
        uninstallerDoneTitle: "Done!",
        uninstallerFreedFormat: "%@ recovered",
        uninstallerSomeFailed: "Some items couldn't be moved to the Trash.",
        uninstallerAnother: "Uninstall another",
        uninstallerCatApp: "Application",
        uninstallerCatSupport: "Support",
        uninstallerCatCaches: "Caches",
        uninstallerCatPreferences: "Preferences",
        uninstallerCatContainers: "Containers",
        uninstallerCatLogs: "Logs",
        uninstallerCatState: "Saved state",
        uninstallerCatOther: "Other",

        urlCleanerName: "Clean URL",
        urlCleanerEnable: "Clean copied URLs",
        urlCleanerEnableCaption: "Removes tracking parameters from copied links.",
        urlCleanerActiveNow: "Active and watching the clipboard",
        urlCleanerManualTitle: "Clean now",
        urlCleanerInputPlaceholder: "Paste a URL",
        urlCleanerOutputPlaceholder: "The clean URL appears here",
        urlCleanerCleanButton: "Clean",
        urlCleanerPasteButton: "Paste",
        urlCleanerCopyButton: "Copy",
        urlCleanerClearButton: "Clear field",
        urlCleanerNoURL: "Paste a valid URL.",
        urlCleanerNoChange: "Nothing to clean.",
        urlCleanerCleaned: "URL cleaned.",
        urlCleanerCopied: "Copied.",
        urlCleanerLocalNote: "Local. No network.",

        shelfName: "Shelf",
        shelfEnable: "Temporary area for dragging files",
        shelfEnableCaption: "A floating spot to gather files, images and text, then drag them anywhere later.",
        shelfHowTitle: "How to use",
        shelfStep1: "Open it with ⌃⌥⌘D, or by shaking the mouse during a drag.",
        shelfStep2: "Drop files, images, links or text onto it to hold them.",
        shelfStep3: "Drag each item back out to any app when you need it.",
        shelfShakeToggle: "Open by shaking the mouse while dragging",
        shelfShakeCaption: "Shake the pointer quickly while holding an item to summon it near the cursor.",
        shelfHotkeyLabel: "Shortcut",
        shelfOpenNow: "Open now",
        shelfNoPermission: "Requires no permissions.",
        shelfMenuItem: "Open shelf",
        shelfTitle: "Shelf",
        shelfEmpty: "Drag items here",
        shelfClearAll: "Clear all",
        shelfRemoveSelected: "Remove selected",
        shelfSelectedFormat: "%d selected",
        shelfHint: "Click to select. Drag out to use.",
        shelfItemImage: "Image",

        breakdownMeasuring: "Measuring…",

        mixerSection: "Volume mixer",
        mixerEmpty: "Apps that use audio show up here",
        mixerUnavailable: "Available on macOS 14.4 and later",
        mixerPermissionBody: "To adjust per-app volume, allow “Screen & System Audio Recording” in System Settings. Audio is never recorded.",
        mixerResetTooltip: "Reset to 100%",

        updatesSection: "Updates",
        autoCheckToggle: "Check for updates automatically",
        checkNowButton: "Check now",
        updateChecking: "Checking…",
        updateUpToDate: "You're on the latest version.",
        updateAvailablePrefix: "Update available:",
        updateInstallButton: "Download and install",
        updateDownloading: "Downloading update…",
        updateInstalling: "Installing and restarting…",
        updateFailedPrefix: "Couldn't check:",
        updateLastChecked: "Last checked:",
        updateNotifyTitle: "Vorssaint update",
        menuCheckUpdates: "Check for updates…",

        permissionRequired: "Permission required",
        permissionAccessibility: "Accessibility",
        permissionScreenRecording: "Screen Recording",
        permissionGranted: "Granted",
        permissionMissing: "Not granted",
        permissionOpenSettings: "Open System Settings…",
        permissionRequest: "Grant access",
        permissionRestartNote: "macOS may ask to reopen the app after granting.",

        aboutDescription: "A utility hub for your Mac.\nEnergy, system monitor, scrolling and a window switcher, right in the menu bar.",
        versionPrefix: "Version",
        reviewIntro: "Review introduction",
        viewOnGitHub: "View on GitHub",

        obContinue: "Continue",
        obBack: "Back",
        obSkipStep: "Skip this step",
        obStart: "Open Vorssaint",
        obStepWelcomeTitle: "Welcome to Vorssaint",
        obStepWelcomeBody: "A discreet menu bar utility that makes everyday macOS more practical.",
        obWelcomeBullet1Title: "Energy under control",
        obWelcomeBullet1Body: "Keep the Mac awake for as long as you want, even with the lid closed.",
        obWelcomeBullet2Title: "A clear view of the system",
        obWelcomeBullet2Body: "CPU, GPU and battery temperatures, hardware usage and memory pressure in real time.",
        obWelcomeBullet3Title: "Mouse and windows, your way",
        obWelcomeBullet3Body: "Reversed mouse scrolling and a window switcher with thumbnails.",
        obLanguageLabel: "Language",
        obStepAccessibilityTitle: "Accessibility",
        obStepAccessibilityBody: "Needed to invert mouse scrolling and for the window switcher to respond to the keyboard.",
        obAccessibilityWhy: "The app only watches the mouse wheel and the switcher shortcut. Nothing is recorded or sent anywhere.",
        obStepRecordingTitle: "Screen Recording",
        obStepRecordingBody: "Lets the switcher show real window thumbnails instead of icons only.",
        obRecordingWhy: "Thumbnails are generated on the fly, stay in memory and never leave your Mac. Without it, the switcher still works with icons.",
        obStepMonitorTitle: "System monitor",
        obStepMonitorBody: "The panel shows CPU, GPU and battery temperatures, hardware usage and memory pressure.",
        obMonitorNoPermission: "No permission needed. Sensors are read straight from the system.",
        obStepOptionalTitle: "Optional features",
        obStepOptionalBody: "Turn on what you want to use now. Everything can be changed later in Settings.",
        obStepStatusTitle: "Checkup",
        obStepStatusBody: "Make sure everything is ready for the features you want.",
        obStatusRecheck: "Check again",
        obStepDoneTitle: "All set!",
        obStepDoneBody: "Vorssaint is already looking after your Mac.",
        obDoneHint: "Look for the black hole in the menu bar, at the top right of the screen.",
        obWhatsNewTitle: "What's new in this version",
        obWhatsNewFallback: "This update includes the latest fixes and improvements.",
        obLanguageUpdateTitle: "Now in your language",
        obLanguageUpdateBody: "Vorssaint now speaks several languages. Choose the one you’d like to use; you can change it anytime in Settings.",

        tabMonitor: "Monitor",
        monitorMenuBarSection: "In the menu bar",
        monitorMenuBarCaption: "Choose what appears next to the icon in the menu bar.",
        monitorShowCPU: "CPU",
        monitorShowMemory: "Memory",
        monitorShowNetwork: "Network",
        monitorShowPowerLabel: "Power",
        monitorIntervalLabel: "Update every",
        monitorInterval1: "1 second",
        monitorInterval2: "2 seconds",
        monitorInterval5: "5 seconds",
        monitorPanelSection: "In the panel",
        panelNavigationMode: "Navigate panel by sections",
        panelNavigationCaption: "Shows one section at a time and places navigation at the bottom of the panel.",
        panelFooterSections: "Sections",
        panelFooterList: "List",
        fanControlBetaShow: "Show Fan Control (Beta) in the panel",
        fanControlBetaSection: "Fan Control",
        fanControlBetaTitle: "Fan Control",
        fanControlBetaStatus: "Automatic",
        fanControlBetaCaption: "Beta. Manual control stays disabled until each Mac model is validated.",
        fanControlModeAutomatic: "Automatic",
        fanControlModeManual: "Manual",
        betaBadge: "BETA",

        networkSection: "Network",
        networkDownload: "Download",
        networkUpload: "Upload",
        networkThisSession: "This session",
        networkMeasuring: "Measuring…",

        powerSection: "Power",
        powerSystem: "System",
        powerAdapter: "Adapter",
        powerBattery: "Battery",
        powerCharging: "Charging",
        powerOnBattery: "On battery",
        powerPluggedIn: "Plugged in",
        powerUnavailable: "Power metrics unavailable on this Mac",
        powerAdapterMaxFormat: "%@ max",
        monitorShowGPU: "GPU",
        monitorGraphsSection: "Graphs",
        monitorGraphsCaption: "Choose which metrics show a graph over time.",

        updateBannerTitle: "Update available",
        updateBannerAction: "Update",
        obStepMenuBarTitle: "Metrics in the menu bar",
        obStepMenuBarBody: "Pick what to show next to the icon. The preview above updates live.",
        obStepMenuBarNote: "New: Network and Power blocks and graphs in the panel. Fine-tune it all later in Settings › Monitor.",
        monitorLabelStyleLabel: "Labels",
        menuBarLabelStyleCompact: "Compact",
        menuBarLabelStyleClassic: "Classic",
        monitorMemoryStyleLabel: "Show memory as",
        memoryStyleDot: "Dot",
        memoryStylePercent: "%",
        memoryStyleBoth: "Both",

        systemUptime: "Up for",
        powerHealth: "Battery health",
        powerCycles: "cycles",
        speedTestRun: "Speed test",
        speedTestAgain: "Test again",
        speedTestLatency: "Latency",
        speedTestTesting: "Testing…",
        speedTestFailed: "Test failed",

        monitorShowInPanel: "Show in panel",
        panelHideItem: "Hide from panel",
        panelShowItem: "Show in panel",
        panelHiddenItem: "Hidden",
        monitorItemUptime: "Uptime",
        monitorItemNetSpeed: "Live speed",
        monitorItemNetTotals: "Session totals",
        monitorItemNetTest: "Speed test",
        monitorPanelConfigHint: "Open a block to choose what it shows.",
        monitorOrderSection: "Section order",
        monitorOrderHint: "Drag to reorder the panel sections. Use each section's chevron in the panel to collapse it.",
        obStepPanelTitle: "What's in the panel",
        obStepPanelBody: "Open each block and pick exactly what shows when you click the icon.",
        obStepPanelNavigationTitle: "Section-based panel",
        obStepPanelNavigationBody: "The panel can now show one section at a time, with navigation at the bottom. It is on for this update so you can try it.",

        cleaningMenuItem: "Cleaning Mode",
        utilitiesSection: "Utilities",
        quickControlsSection: "Controls",
        windowMaximizeName: "Maximize windows",
        windowMaximizeCaption: "The green button maximizes without creating another Space.",
        windowMaximizeActiveNow: "Green button override active",
        windowMaximizeNeedsAccessibility: "Needs Accessibility to work.",
        cleaningPanelCaption: "Locks the keyboard so you can clean safely.",
        cleaningOverlayTitle: "Keyboard locked for cleaning",
        cleaningOverlaySubtitle: "Press the same key 5 times to unlock",
        cleaningOverlayUnlock: "Unlock",
        cleaningOverlayMouseHint: "Your mouse and trackpad still work",
        cleaningNeedsAxTitle: "Accessibility needed",
        cleaningNeedsAxBody: "To lock the keyboard safely, Vorssaint needs Accessibility permission. Grant it in System Settings and try again.",

        tabSupport: "Support",
        donateHeading: "Support Vorssaint",
        donateMessage: "Every one of my public projects is, and always will be, completely free: no subscription, no ads. Community support is the only thing that keeps it alive. If Vorssaint helps you, a coffee genuinely makes a difference.",
        donateButton: "Buy me a coffee",
        donateThanks: "Thank you for being here. 🖤",
        showMenuBarIcon: "Show menu bar icon",
        showMenuBarIconCaption: "If Vorssaint's icon disappears (macOS can hide menu bar icons when the bar runs out of room, common on Macs with a notch), reopen Vorssaint from Applications or Spotlight: that rebuilds the icon and, if it's still hidden, opens this window. The button above does the same when you can already get here. Keeping fewer menu bar icons, or fewer Vorssaint metrics, makes it far less likely."
    )
}
