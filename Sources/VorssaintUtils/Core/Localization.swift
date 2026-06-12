import Combine
import Foundation

/// Languages the interface can use. The first launch defaults to the system
/// language; the onboarding and Settings let the user override it at any time.
enum AppLanguage: String, CaseIterable, Identifiable {
    case ptBR = "pt-BR"
    case enUS = "en-US"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ptBR: return "Português (Brasil)"
        case .enUS: return "English (US)"
        }
    }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("pt") == true ? .ptBR : .enUS
    }
}

/// Source of every user-facing string. Views observe this object so the whole
/// interface re-renders immediately when the language changes.
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.language) }
    }

    var s: Strings { language == .ptBR ? .ptBR : .enUS }

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
    let panelActiveBadge: String
    let panelSettings: String
    let panelQuit: String
    let panelHotkeyHint: String

    // MARK: Panel — keep awake card
    let keepAwakeTitle: String
    let keepAwakeEndsIn: String        // + remaining
    let keepAwakeUntilDisabled: String
    let keepAwakeNormalRules: String
    let durationLabel: String
    let keepDisplayOn: String
    let clamshellTitle: String
    let clamshellOnCaption: String
    let clamshellNeedsSession: String
    let clamshellReady: String
    let clamshellNeedsPassword: String

    // MARK: Panel — utilities
    let utilitiesSection: String
    let hideDesktopIcons: String
    let showHiddenFiles: String
    let turnOffDisplay: String
    let ejectDisks: String
    let emptyTrash: String
    let confirmQuestion: String
    let ejectFailed: String
    let trashFailed: String

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

    // MARK: Notifications
    let notifySessionEndedTitle: String
    let notifySessionEndedBody: String
    let notifyBatteryTitle: String
    let notifyBatteryBody: String

    // MARK: Administrator prompts (shown by macOS password dialogs)
    let adminPromptClamshellOn: String
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
    let tabAbout: String

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
    let keepDisplayCaption: String
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
    let scrollLiveNote: String
    let scrollActiveNow: String

    // MARK: Settings — switcher
    let switcherSection: String
    let switcherEnable: String
    let switcherEnableCaption: String
    let switcherUsageHint: String
    let switcherNoWindows: String
    let switcherTabsToggle: String
    let switcherTabsCaption: String

    // MARK: Panel — per-app breakdown
    let breakdownMeasuring: String

    // MARK: Panel — volume mixer
    let mixerSection: String
    let mixerEmpty: String
    let mixerUnavailable: String
    let mixerPermissionBody: String

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
    let obPasswordlessToggle: String
    let obPasswordlessCaption: String
    let obStepStatusTitle: String
    let obStepStatusBody: String
    let obStatusRecheck: String
    let obStepDoneTitle: String
    let obStepDoneBody: String
    let obDoneHint: String
}

// MARK: - Português (Brasil)

extension Strings {
    static let ptBR = Strings(
        statusIdleTooltip: "Vorssaint Utils — suspensão normal",
        statusActiveUntil: "Vorssaint Utils — ativo até",
        statusActiveIndefinite: "Vorssaint Utils — ativo indefinidamente",
        menuEnableAwake: "Ativar manter acordado",
        menuDisableAwake: "Desativar manter acordado",
        menuActivateFor: "Ativar por…",
        menuSettings: "Ajustes…",
        menuAbout: "Sobre o Vorssaint Utils",
        menuQuit: "Sair do Vorssaint Utils",

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
        panelActiveBadge: "ATIVO",
        panelSettings: "Ajustes",
        panelQuit: "Sair",
        panelHotkeyHint: "⌃⌥⌘K alterna",

        keepAwakeTitle: "Manter acordado",
        keepAwakeEndsIn: "Termina em",
        keepAwakeUntilDisabled: "Ativo até você desativar",
        keepAwakeNormalRules: "O Mac segue as regras normais de energia",
        durationLabel: "Duração",
        keepDisplayOn: "Manter a tela ligada",
        clamshellTitle: "Continuar com a tampa fechada",
        clamshellOnCaption: "Suspensão totalmente desativada — atenção à energia",
        clamshellNeedsSession: "Será aplicada sempre que “Manter acordado” estiver ativo",
        clamshellReady: "Pronto — liga e desliga sem senha",
        clamshellNeedsPassword: "Pedirá a senha de administrador ao ativar",

        utilitiesSection: "Utilidades",
        hideDesktopIcons: "Ocultar ícones da mesa",
        showHiddenFiles: "Mostrar arquivos ocultos",
        turnOffDisplay: "Desligar tela",
        ejectDisks: "Ejetar discos",
        emptyTrash: "Esvaziar Lixeira",
        confirmQuestion: "Confirmar?",
        ejectFailed: "Não foi possível ejetar os discos.",
        trashFailed: "Não foi possível esvaziar a Lixeira.",

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

        notifySessionEndedTitle: "Sessão encerrada",
        notifySessionEndedBody: "O tempo acabou — o Mac voltará a suspender normalmente.",
        notifyBatteryTitle: "Vorssaint Utils desativado",
        notifyBatteryBody: "Bateria baixa — a suspensão normal foi restaurada para proteger a carga.",

        adminPromptClamshellOn: "O Vorssaint Utils precisa da sua senha para manter o Mac ativo com a tampa fechada. Dispense este pedido na introdução do app (Ajustes › Sobre).",
        adminPromptClamshellOff: "O Vorssaint Utils precisa da sua senha para reativar a suspensão normal do Mac.",
        adminPromptRecover: "O Vorssaint Utils foi encerrado com a suspensão do Mac desativada. Digite a senha para restaurar a suspensão normal.",
        adminPromptSudoersInstall: "O Vorssaint Utils vai criar uma regra restrita (somente pmset disablesleep) para alternar a tampa fechada sem pedir senha. Esta é a única vez que a senha será necessária.",
        adminPromptSudoersRemove: "O Vorssaint Utils vai remover a regra de tampa fechada sem senha.",

        settingsTitle: "Ajustes do Vorssaint Utils",
        tabGeneral: "Geral",
        tabEnergy: "Energia",
        tabMouse: "Mouse",
        tabSwitcher: "Alternador",
        tabAbout: "Sobre",

        launchAtLogin: "Iniciar junto com o Mac",
        languageLabel: "Idioma",
        menuBarSection: "Barra de menus",
        showCountdown: "Mostrar tempo restante ao lado do ícone",
        globalHotkeySection: "Atalho global",
        hotkeyToggle: "Alternar “Manter acordado” com ⌃⌥⌘K",
        hotkeyCaption: "Funciona em qualquer app, sem permissões extras.",

        sessionSection: "Sessão",
        defaultDurationLabel: "Duração padrão",
        keepDisplayCaption: "Com a tela desligada, o Mac continua acordado para downloads, builds e servidores.",
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
        invertMouseScrollCaption: "A roda do mouse passa a rolar como no Windows.",
        scrollTrackpadNote: "O trackpad não muda: continua com a rolagem natural do macOS.",
        scrollLiveNote: "A mudança vale na hora, sem reiniciar nada.",
        scrollActiveNow: "Invertendo a rolagem do mouse agora",

        switcherSection: "Alternador de apps",
        switcherEnable: "Substituir o ⌘Tab pelo alternador do Vorssaint Utils",
        switcherEnableCaption: "Troque de janela vendo miniaturas reais, como o Alt+Tab do Windows.",
        switcherUsageHint: "Segure ⌘ e toque Tab para navegar; solte para ativar a janela. Shift ou ← volta; Q fecha o app selecionado; Esc cancela.",
        switcherNoWindows: "Nenhuma janela aberta",
        switcherTabsToggle: "Mostrar abas dos navegadores",
        switcherTabsCaption: "Cada aba do Safari, Chrome, Edge, Brave ou Vivaldi vira uma entrada no alternador. O macOS pede permissão de automação na primeira vez, por navegador.",

        breakdownMeasuring: "Medindo…",

        mixerSection: "Mixer de volume",
        mixerEmpty: "Nada reproduzindo áudio agora",
        mixerUnavailable: "Disponível a partir do macOS 14.4",
        mixerPermissionBody: "Para ajustar o volume por app, permita “Gravação de Tela e Áudio do Sistema” nos Ajustes do Sistema. O áudio nunca é gravado.",

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
        updateNotifyTitle: "Atualização do Vorssaint Utils",
        menuCheckUpdates: "Procurar atualizações…",

        permissionRequired: "Permissão necessária",
        permissionAccessibility: "Acessibilidade",
        permissionScreenRecording: "Gravação de Tela",
        permissionGranted: "Concedida",
        permissionMissing: "Não concedida",
        permissionOpenSettings: "Abrir Ajustes do Sistema…",
        permissionRequest: "Pedir permissão",
        permissionRestartNote: "O macOS pode pedir para reabrir o app depois de conceder.",

        aboutDescription: "Central de utilidades para o seu Mac.\nEnergia, monitor do sistema, rolagem e alternador de janelas — direto na barra de menus.",
        versionPrefix: "Versão",
        reviewIntro: "Rever introdução",
        viewOnGitHub: "Ver no GitHub",

        obContinue: "Continuar",
        obBack: "Voltar",
        obSkipStep: "Pular esta etapa",
        obStart: "Abrir o Vorssaint Utils",
        obStepWelcomeTitle: "Bem-vindo ao Vorssaint Utils",
        obStepWelcomeBody: "Um utilitário discreto na barra de menus que deixa o macOS mais prático no dia a dia.",
        obWelcomeBullet1Title: "Energia sob controle",
        obWelcomeBullet1Body: "Mantenha o Mac acordado por quanto tempo quiser, até com a tampa fechada.",
        obWelcomeBullet2Title: "Visão clara do sistema",
        obWelcomeBullet2Body: "Temperaturas, uso de CPU e GPU e pressão de memória em tempo real.",
        obWelcomeBullet3Title: "Mouse e janelas do seu jeito",
        obWelcomeBullet3Body: "Rolagem estilo Windows no mouse e um alternador de janelas com miniaturas.",
        obLanguageLabel: "Idioma",
        obStepAccessibilityTitle: "Acessibilidade",
        obStepAccessibilityBody: "Necessária para inverter a rolagem do mouse e para o alternador de janelas responder ao teclado.",
        obAccessibilityWhy: "O app só observa a roda do mouse e o atalho do alternador. Nada é gravado nem enviado a lugar algum.",
        obStepRecordingTitle: "Gravação de Tela",
        obStepRecordingBody: "Permite mostrar miniaturas reais das janelas no alternador, em vez de apenas ícones.",
        obRecordingWhy: "As miniaturas são geradas na hora, ficam só na memória e nunca saem do seu Mac. Sem ela, o alternador funciona com ícones.",
        obStepMonitorTitle: "Monitor do sistema",
        obStepMonitorBody: "O painel mostra as temperaturas de CPU, GPU e bateria, o uso de hardware e a pressão de memória.",
        obMonitorNoPermission: "Não precisa de permissão — os sensores são lidos direto do sistema.",
        obStepOptionalTitle: "Recursos opcionais",
        obStepOptionalBody: "Ative agora o que quiser usar. Tudo pode ser mudado depois nos Ajustes.",
        obPasswordlessToggle: "Tampa fechada sem pedir senha",
        obPasswordlessCaption: "Cria uma regra do sistema restrita a “pmset disablesleep”. A senha de administrador é pedida uma única vez, agora.",
        obStepStatusTitle: "Verificação",
        obStepStatusBody: "Confira se está tudo pronto para os recursos que você quer usar.",
        obStatusRecheck: "Verificar novamente",
        obStepDoneTitle: "Tudo pronto!",
        obStepDoneBody: "O Vorssaint Utils já está cuidando do seu Mac.",
        obDoneHint: "Procure o buraco negro na barra de menus, no canto superior direito da tela."
    )
}

// MARK: - English (US)

extension Strings {
    static let enUS = Strings(
        statusIdleTooltip: "Vorssaint Utils — normal sleep",
        statusActiveUntil: "Vorssaint Utils — awake until",
        statusActiveIndefinite: "Vorssaint Utils — awake indefinitely",
        menuEnableAwake: "Enable keep awake",
        menuDisableAwake: "Disable keep awake",
        menuActivateFor: "Activate for…",
        menuSettings: "Settings…",
        menuAbout: "About Vorssaint Utils",
        menuQuit: "Quit Vorssaint Utils",

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
        panelActiveBadge: "ACTIVE",
        panelSettings: "Settings",
        panelQuit: "Quit",
        panelHotkeyHint: "⌃⌥⌘K toggles",

        keepAwakeTitle: "Keep awake",
        keepAwakeEndsIn: "Ends in",
        keepAwakeUntilDisabled: "Active until you turn it off",
        keepAwakeNormalRules: "The Mac follows its normal energy rules",
        durationLabel: "Duration",
        keepDisplayOn: "Keep the display on",
        clamshellTitle: "Keep going with the lid closed",
        clamshellOnCaption: "Sleep fully disabled — mind the power",
        clamshellNeedsSession: "Applied whenever “Keep awake” is active",
        clamshellReady: "Ready — toggles without a password",
        clamshellNeedsPassword: "Will ask for the administrator password when enabling",

        utilitiesSection: "Utilities",
        hideDesktopIcons: "Hide desktop icons",
        showHiddenFiles: "Show hidden files",
        turnOffDisplay: "Turn off display",
        ejectDisks: "Eject disks",
        emptyTrash: "Empty Trash",
        confirmQuestion: "Confirm?",
        ejectFailed: "The disks could not be ejected.",
        trashFailed: "The Trash could not be emptied.",

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

        notifySessionEndedTitle: "Session ended",
        notifySessionEndedBody: "Time is up — the Mac will sleep normally again.",
        notifyBatteryTitle: "Vorssaint Utils disabled",
        notifyBatteryBody: "Low battery — normal sleep was restored to protect the charge.",

        adminPromptClamshellOn: "Vorssaint Utils needs your password to keep the Mac awake with the lid closed. Waive this prompt in the app introduction (Settings › About).",
        adminPromptClamshellOff: "Vorssaint Utils needs your password to restore the Mac's normal sleep.",
        adminPromptRecover: "Vorssaint Utils quit while the Mac's sleep was disabled. Enter the password to restore normal sleep.",
        adminPromptSudoersInstall: "Vorssaint Utils will create a restricted rule (pmset disablesleep only) to toggle closed-lid mode without asking for a password. This is the only time the password is needed.",
        adminPromptSudoersRemove: "Vorssaint Utils will remove the password-free closed-lid rule.",

        settingsTitle: "Vorssaint Utils Settings",
        tabGeneral: "General",
        tabEnergy: "Energy",
        tabMouse: "Mouse",
        tabSwitcher: "Switcher",
        tabAbout: "About",

        launchAtLogin: "Launch at login",
        languageLabel: "Language",
        menuBarSection: "Menu bar",
        showCountdown: "Show remaining time next to the icon",
        globalHotkeySection: "Global shortcut",
        hotkeyToggle: "Toggle “Keep awake” with ⌃⌥⌘K",
        hotkeyCaption: "Works in any app, no extra permissions.",

        sessionSection: "Session",
        defaultDurationLabel: "Default duration",
        keepDisplayCaption: "With the display off, the Mac stays awake for downloads, builds and servers.",
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
        invertMouseScrollCaption: "The mouse wheel scrolls like it does on Windows.",
        scrollTrackpadNote: "The trackpad is untouched: it keeps macOS natural scrolling.",
        scrollLiveNote: "Takes effect immediately, nothing to restart.",
        scrollActiveNow: "Inverting mouse scrolling right now",

        switcherSection: "App switcher",
        switcherEnable: "Replace ⌘Tab with the Vorssaint Utils switcher",
        switcherEnableCaption: "Switch windows with real thumbnails, like Alt+Tab on Windows.",
        switcherUsageHint: "Hold ⌘ and tap Tab to navigate; release to activate the window. Shift or ← goes back; Q quits the selected app; Esc cancels.",
        switcherNoWindows: "No open windows",
        switcherTabsToggle: "Show browser tabs",
        switcherTabsCaption: "Every Safari, Chrome, Edge, Brave or Vivaldi tab becomes a switcher entry. macOS asks for Automation consent once per browser.",

        breakdownMeasuring: "Measuring…",

        mixerSection: "Volume mixer",
        mixerEmpty: "Nothing playing audio right now",
        mixerUnavailable: "Available on macOS 14.4 and later",
        mixerPermissionBody: "To adjust per-app volume, allow “Screen & System Audio Recording” in System Settings. Audio is never recorded.",

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
        updateNotifyTitle: "Vorssaint Utils update",
        menuCheckUpdates: "Check for updates…",

        permissionRequired: "Permission required",
        permissionAccessibility: "Accessibility",
        permissionScreenRecording: "Screen Recording",
        permissionGranted: "Granted",
        permissionMissing: "Not granted",
        permissionOpenSettings: "Open System Settings…",
        permissionRequest: "Request permission",
        permissionRestartNote: "macOS may ask to reopen the app after granting.",

        aboutDescription: "A utility hub for your Mac.\nEnergy, system monitor, scrolling and a window switcher — right in the menu bar.",
        versionPrefix: "Version",
        reviewIntro: "Review introduction",
        viewOnGitHub: "View on GitHub",

        obContinue: "Continue",
        obBack: "Back",
        obSkipStep: "Skip this step",
        obStart: "Open Vorssaint Utils",
        obStepWelcomeTitle: "Welcome to Vorssaint Utils",
        obStepWelcomeBody: "A discreet menu bar utility that makes everyday macOS more practical.",
        obWelcomeBullet1Title: "Energy under control",
        obWelcomeBullet1Body: "Keep the Mac awake for as long as you want, even with the lid closed.",
        obWelcomeBullet2Title: "A clear view of the system",
        obWelcomeBullet2Body: "CPU, GPU and battery temperatures, hardware usage and memory pressure in real time.",
        obWelcomeBullet3Title: "Mouse and windows, your way",
        obWelcomeBullet3Body: "Windows-style scrolling for the mouse and a window switcher with thumbnails.",
        obLanguageLabel: "Language",
        obStepAccessibilityTitle: "Accessibility",
        obStepAccessibilityBody: "Needed to invert mouse scrolling and for the window switcher to respond to the keyboard.",
        obAccessibilityWhy: "The app only watches the mouse wheel and the switcher shortcut. Nothing is recorded or sent anywhere.",
        obStepRecordingTitle: "Screen Recording",
        obStepRecordingBody: "Lets the switcher show real window thumbnails instead of icons only.",
        obRecordingWhy: "Thumbnails are generated on the fly, stay in memory and never leave your Mac. Without it, the switcher still works with icons.",
        obStepMonitorTitle: "System monitor",
        obStepMonitorBody: "The panel shows CPU, GPU and battery temperatures, hardware usage and memory pressure.",
        obMonitorNoPermission: "No permission needed — sensors are read straight from the system.",
        obStepOptionalTitle: "Optional features",
        obStepOptionalBody: "Turn on what you want to use now. Everything can be changed later in Settings.",
        obPasswordlessToggle: "Closed lid without a password prompt",
        obPasswordlessCaption: "Creates a system rule restricted to “pmset disablesleep”. The administrator password is asked once, now.",
        obStepStatusTitle: "Checkup",
        obStepStatusBody: "Make sure everything is ready for the features you want.",
        obStatusRecheck: "Check again",
        obStepDoneTitle: "All set!",
        obStepDoneBody: "Vorssaint Utils is already looking after your Mac.",
        obDoneHint: "Look for the black hole in the menu bar, at the top right of the screen."
    )
}
