// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UserNotifications

/// One Settings home for the installable Cleaner module. The system cleaner
/// and WhatsApp downloads keep separate controls and schedules, while sharing
/// the module's availability and permission portal entry.
struct CleanerSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @AppStorage(DefaultsKey.whatsAppDownloadsEnabled) private var whatsAppEnabled = false
    @State private var tool = Tool.system

    private enum Tool: String {
        case system, whatsApp
    }

    /// A panel surface can ask for a specific tool; the hint is one-shot.
    private func consumeToolHint() {
        guard let hint = router.cleanerTool else { return }
        router.cleanerTool = nil
        guard whatsAppEnabled, let wanted = Tool(rawValue: hint) else { return }
        tool = wanted
    }

    var body: some View {
        VStack(spacing: 0) {
            if whatsAppEnabled {
                Picker("", selection: $tool) {
                    Label(l10n.s.cleanerName, systemImage: "sparkles")
                        .tag(Tool.system)
                    Label(FeatureStrings.whatsAppDownloads(l10n.language).title,
                          systemImage: "arrow.down.doc")
                        .tag(Tool.whatsApp)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 440)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                Divider()
            }

            if whatsAppEnabled, tool == .whatsApp {
                WhatsAppDownloadsSettings()
            } else {
                CleanerView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if !whatsAppEnabled { tool = .system }
            consumeToolHint()
        }
        .onChange(of: router.cleanerTool) { _, _ in consumeToolHint() }
        .onChange(of: whatsAppEnabled) { _, enabled in
            tool = enabled ? .whatsApp : .system
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
            if !enabled {
                WhatsAppDownloadManager.shared.reset()
                WhatsAppDownloadOrganizer.shared.stop()
            }
        }
    }
}

/// The junk cleaner, built for one glance: a safe section that is fully
/// selected and ready for a single click, and an optional section that
/// starts unchecked and collapsed for whoever wants to dig. Every group has
/// a plain language explanation; the file by file detail lives one chevron
/// away instead of in your face. Hosted by the menu bar panel and the quick
/// panel.
struct CleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var cleaner = JunkCleaner.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var navigator = PanelKeyboardNavigator.shared
    @AppStorage(DefaultsKey.cleanerScheduleFrequency) private var scheduleFrequencyRaw = "off"
    @AppStorage(DefaultsKey.cleanerScheduleHour) private var scheduleHour = 9
    @AppStorage(DefaultsKey.cleanerScheduleMinute) private var scheduleMinute = 0
    @AppStorage(DefaultsKey.cleanerScheduleWeekday) private var scheduleWeekday = 2
    @AppStorage(DefaultsKey.cleanerLastAutoRun) private var lastAutoRun = 0.0
    @AppStorage(DefaultsKey.cleanerLastAutoFreed) private var lastAutoFreed = 0
    @AppStorage(DefaultsKey.cleanerScheduleNotify) private var scheduleNotify = true
    @ObservedObject private var scheduler = CleanerScheduler.shared
    @ObservedObject private var whatsAppScheduler = WhatsAppDownloadScheduler.shared
    @AppStorage(DefaultsKey.whatsAppDownloadsEnabled) private var whatsAppEnabled = false
    @AppStorage(DefaultsKey.whatsAppDownloadsAutomaticEnabled) private var whatsAppAutomatic = false
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanup) private var whatsAppLastCleanup = 0.0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupCount) private var whatsAppLastCount = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupBytes) private var whatsAppLastBytes = 0
    @AppStorage(DefaultsKey.whatsAppDownloadsLastCleanupFailed) private var whatsAppLastFailed = 0
    @State private var notificationsDenied = false
    /// The panel hosted card starts folded; the Settings page shows it open.
    @State private var scheduleExpanded = false
    @State private var whatsAppExpanded = false
    @State private var expandedGroups: Set<DisplayGroup> = []
    /// Tightens paddings for the panel and launcher.
    var compact = false
    /// Non-nil only when hosted in the menu panel; Settings and the launcher
    /// retain their native keyboard behavior.
    var keyboardSection: PanelSectionID? = nil

    var body: some View {
        content
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch cleaner.phase {
        case .idle: settingsScrolling(idleState)
        case .scanning: settingsScrolling(busyState(l10n.s.cleanerScanning, detail: scanningDetail))
        case .results: resultsState
        case .cleaning: settingsScrolling(busyState(l10n.s.cleanerCleaning, detail: nil))
        case let .done(freed, failed): settingsScrolling(doneState(freed: freed, failed: failed))
        }
    }

    /// On the Settings page every detail must host a scroll container: the
    /// split view's sidebar loses its title bar safe area otherwise (macOS 27
    /// beta) and its rows draw under the toolbar or vanish. Every other page
    /// is a Form and gets this for free; the cleaner's List state scrolls on
    /// its own, and these centered states scroll here — the minHeight keeps
    /// them vertically centered exactly as before. The panel keeps the plain
    /// layout: it never sits inside the split view.
    @ViewBuilder
    private func settingsScrolling(_ view: some View) -> some View {
        if compact {
            view
        } else {
            GeometryReader { proxy in
                ScrollView {
                    view.frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
    }

    /// The cleaner's waiting face: the sparkles glyph twinkling layer by
    /// layer through the system symbol effect. Simple, native, and still
    /// while nothing is happening.
    private struct SparkleGlyph: View {
        var animating = false
        var size: CGFloat = 44

        var body: some View {
            Image(systemName: "sparkles")
                .font(.system(size: size, weight: .light))
                .foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative.reversing,
                              options: .repeating, isActive: animating)
        }
    }

    private var scanningDetail: String? {
        cleaner.scanningCategory.flatMap { category in
            DisplayGroup.allCases.first { $0.categories.contains(category) }
        }.map(title(for:))
    }

    // MARK: Display groups

    /// How the raw finds are presented: safe groups first, fully selected;
    /// judgment calls under optional, unchecked and collapsed.
    private enum DisplayGroup: Int, CaseIterable, Identifiable {
        case loginItems, safeCaches, logs, developer
        case leftovers, otherCaches, deviceBackups, trash

        var id: Int { rawValue }

        var isSafe: Bool {
            switch self {
            case .loginItems, .safeCaches, .logs, .developer: return true
            case .leftovers, .otherCaches, .deviceBackups, .trash: return false
            }
        }

        var categories: [CleanerSupport.Category] {
            switch self {
            case .loginItems: return [.loginItems]
            case .safeCaches, .otherCaches: return [.caches]
            case .logs: return [.logs]
            case .developer: return [.developer]
            case .leftovers: return [.leftovers]
            case .deviceBackups: return [.deviceBackups]
            case .trash: return [.trash]
            }
        }

        var icon: String {
            switch self {
            case .loginItems: return "power"
            case .safeCaches: return "archivebox"
            case .logs: return "doc.text"
            case .developer: return "hammer"
            case .leftovers: return "puzzlepiece"
            case .otherCaches: return "internaldrive"
            case .deviceBackups: return "iphone"
            case .trash: return "trash"
            }
        }
    }

    private func items(for group: DisplayGroup) -> [JunkCleaner.Item] {
        switch group {
        case .safeCaches: return cleaner.items.filter { $0.category == .caches && $0.recommended }
        case .otherCaches: return cleaner.items.filter { $0.category == .caches && !$0.recommended }
        default: return cleaner.items.filter { group.categories.contains($0.category) }
        }
    }

    private func title(for group: DisplayGroup) -> String {
        switch group {
        case .loginItems: return l10n.s.cleanerCatLoginItems
        case .safeCaches: return l10n.s.cleanerCatCaches
        case .logs: return l10n.s.cleanerCatLogs
        case .developer: return l10n.s.cleanerCatDeveloper
        case .leftovers: return l10n.s.cleanerCatLeftovers
        case .otherCaches: return l10n.s.cleanerCatOtherCaches
        case .deviceBackups: return l10n.s.cleanerCatDeviceBackups
        case .trash: return l10n.s.cleanerCatTrash
        }
    }

    private func caption(for group: DisplayGroup) -> String {
        switch group {
        case .loginItems: return l10n.s.cleanerLoginItemsCaption
        case .safeCaches: return l10n.s.cleanerCachesCaption
        case .logs: return l10n.s.cleanerLogsCaption
        case .developer: return l10n.s.cleanerDeveloperCaption
        case .leftovers: return l10n.s.cleanerLeftoversCaption
        case .otherCaches: return l10n.s.cleanerOtherCachesCaption
        case .deviceBackups: return l10n.s.cleanerDeviceBackupsCaption
        case .trash: return l10n.s.cleanerTrashNote
        }
    }

    // MARK: Idle

    private var idleState: some View {
        VStack(spacing: compact ? 12 : 18) {
            if !compact { Spacer() }
            SparkleGlyph(size: compact ? 34 : 46)
            Text(l10n.s.cleanerIntroTitle)
                .font(.system(size: compact ? 15 : 17, weight: .semibold))
            Text(l10n.s.cleanerIntroCaption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            Button(l10n.s.cleanerScan) { cleaner.scan() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .panelKeyboardRow(keyboardRow("cleaner-scan"),
                                  actions: PanelRowActions(activate: { cleaner.scan() }))
            scheduleCard
            if !compact, !whatsAppEnabled { whatsAppOptInCard }
            // The Settings page has its own full tool for these downloads;
            // the panel gets this one-line home so the feature is findable
            // without opening Settings.
            if compact, whatsAppEnabled { whatsAppCard }
            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: compact, keyboardSection: keyboardSection).frame(maxWidth: 380)
            }
            if !compact { Spacer() }
        }
        .padding(compact ? 14 : 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: WhatsApp downloads (panel surface)

    private var whatsAppStrings: WhatsAppDownloadStrings {
        FeatureStrings.whatsAppDownloads(l10n.language)
    }

    private var whatsAppOptInCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(whatsAppStrings.title, isOn: $whatsAppEnabled)
                .font(.system(size: 12, weight: .medium))
            Text(whatsAppStrings.hubDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Collapsed summary: Off until the automation is armed, then the next
    /// pass, so the row answers "is it working?" without being opened.
    private var whatsAppSummary: String {
        guard whatsAppAutomatic else { return l10n.s.cleanerScheduleOff }
        if let next = whatsAppScheduler.nextFire {
            return Self.nextRunFormatter.string(from: next)
        }
        return whatsAppStrings.automatic
    }

    /// The cleanup's one-line home in the panel: state at a glance, the last
    /// and next pass when expanded, and a jump straight into its settings.
    private var whatsAppCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    whatsAppExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: whatsAppExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 9)
                    Image(systemName: "arrow.down.doc").foregroundStyle(.secondary)
                    Text(whatsAppStrings.title)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(whatsAppSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelKeyboardRow(keyboardRow("cleaner-whatsAppDisclosure"), actions: PanelRowActions(
                activate: toggleWhatsAppExpanded,
                adjust: adjustWhatsAppDisclosure))

            if whatsAppExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if whatsAppLastCleanup > 0 {
                        Text(String(format: whatsAppStrings.lastRunFormat,
                                    Self.nextRunFormatter.string(
                                        from: Date(timeIntervalSince1970: whatsAppLastCleanup)),
                                    whatsAppLastCount,
                                    Self.byteString(Int64(whatsAppLastBytes)),
                                    whatsAppLastFailed))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(whatsAppStrings.neverRun)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if whatsAppAutomatic, let next = whatsAppScheduler.nextFire {
                        Text(String(format: whatsAppStrings.nextRunFormat,
                                    Self.nextRunFormatter.string(from: next)))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(whatsAppStrings.manageButton) {
                        SettingsRouter.shared.cleanerTool = "whatsApp"
                        SettingsRouter.shared.request(FeatureSettingsDestination(.cleaner))
                        appDelegate()?.openSettingsWindow()
                    }
                    .controlSize(.small)
                    .panelKeyboardRow(keyboardRow("cleaner-whatsAppManage"), actions: PanelRowActions(activate: {
                        SettingsRouter.shared.cleanerTool = "whatsApp"
                        SettingsRouter.shared.request(FeatureSettingsDestination(.cleaner))
                        appDelegate()?.openSettingsWindow()
                    }))
                }
                .padding(.horizontal, 11)
                .padding(.top, 5)
                .padding(.bottom, 11)
            }
        }
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    // MARK: Automatic cleanup

    private var scheduleFrequency: CleanerSchedule.Frequency {
        CleanerSchedule.Frequency.sanitized(scheduleFrequencyRaw)
    }

    /// Whether the user's clock runs on twelve hours (6 PM) or twenty four
    /// (18:00); the pickers follow whatever the Mac is set to.
    private static let uses12HourClock: Bool = {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0,
                                              locale: Locale.current) ?? ""
        return format.contains("a")
    }()

    private static let dayPeriodSymbols: (am: String, pm: String) = {
        let formatter = DateFormatter()
        return (formatter.amSymbol ?? "AM", formatter.pmSymbol ?? "PM")
    }()

    /// The stored hour split for the twelve hour pickers: hour, then
    /// minutes, then AM or PM.
    private var scheduleHour12Binding: Binding<Int> {
        Binding(
            get: { CleanerSchedule.hour12Components(fromHour24: scheduleHour).hour12 },
            set: { newValue in
                let isPM = CleanerSchedule.hour12Components(fromHour24: scheduleHour).isPM
                scheduleHour = CleanerSchedule.hour24(hour12: newValue, isPM: isPM)
            }
        )
    }

    private var schedulePMBinding: Binding<Bool> {
        Binding(
            get: { CleanerSchedule.hour12Components(fromHour24: scheduleHour).isPM },
            set: { isPM in
                let hour12 = CleanerSchedule.hour12Components(fromHour24: scheduleHour).hour12
                scheduleHour = CleanerSchedule.hour24(hour12: hour12, isPM: isPM)
            }
        )
    }

    /// Five minute steps, plus the stored value when it falls off the grid.
    private var minuteChoices: [Int] {
        var minutes = Array(stride(from: 0, through: 55, by: 5))
        if !minutes.contains(scheduleMinute), (0...59).contains(scheduleMinute) {
            minutes.append(scheduleMinute)
            minutes.sort()
        }
        return minutes
    }

    private static let nextRunFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private var scheduleSummary: String {
        switch scheduleFrequency {
        case .off: return l10n.s.cleanerScheduleOff
        case .daily: return l10n.s.cleanerScheduleDaily
        case .weekly: return l10n.s.cleanerScheduleWeekly
        }
    }

    private var frequencyPicker: some View {
        Picker("", selection: $scheduleFrequencyRaw) {
            Text(l10n.s.cleanerScheduleOff).tag(CleanerSchedule.Frequency.off.rawValue)
            Text(l10n.s.cleanerScheduleDaily).tag(CleanerSchedule.Frequency.daily.rawValue)
            Text(l10n.s.cleanerScheduleWeekly).tag(CleanerSchedule.Frequency.weekly.rawValue)
        }
        .labelsHidden()
        .fixedSize()
        .panelKeyboardRow(keyboardRow("cleaner-scheduleFrequency"), actions: PanelRowActions(adjust: adjustFrequency))
    }

    /// The schedule in one small card: a frequency and, once it is on, the
    /// weekday and time as plain menus, a live "next cleanup" line proving
    /// the schedule armed, and the notification choice with its permission
    /// state in the open. Hosted in the panels the card folds to one quiet
    /// line with the current state; the Settings page shows it whole.
    @ViewBuilder
    private var scheduleCard: some View {
        if compact {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scheduleExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: scheduleExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 9)
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text(l10n.s.cleanerScheduleTitle)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(scheduleSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .panelKeyboardRow(keyboardRow("cleaner-scheduleDisclosure"), actions: PanelRowActions(
                    activate: toggleScheduleExpanded,
                    adjust: adjustScheduleDisclosure))

                if scheduleExpanded {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { frequencyPicker; Spacer() }
                        scheduleDetails
                        Text(l10n.s.cleanerScheduleCaption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.top, 5)
                    .padding(.bottom, 11)
                }
            }
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
            .modifier(ScheduleChangeSync(notify: $scheduleNotify,
                                         frequency: $scheduleFrequencyRaw,
                                         hour: $scheduleHour,
                                         minute: $scheduleMinute,
                                         weekday: $scheduleWeekday,
                                         refresh: refreshNotificationStatus))
        } else {
            fullScheduleCard
        }
    }

    private var fullScheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text(l10n.s.cleanerScheduleTitle)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                frequencyPicker
            }
            scheduleDetails
            Text(l10n.s.cleanerScheduleCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.05)))
        .modifier(ScheduleChangeSync(notify: $scheduleNotify,
                                     frequency: $scheduleFrequencyRaw,
                                     hour: $scheduleHour,
                                     minute: $scheduleMinute,
                                     weekday: $scheduleWeekday,
                                     refresh: refreshNotificationStatus))
    }

    @ViewBuilder
    private var scheduleDetails: some View {
        if scheduleFrequency != .off {
                HStack(spacing: 6) {
                    if scheduleFrequency == .weekly {
                        Picker("", selection: $scheduleWeekday) {
                            ForEach(1...7, id: \.self) { day in
                                Text(Calendar.current.standaloneWeekdaySymbols[day - 1].capitalized)
                                    .tag(day)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .panelKeyboardRow(keyboardRow("cleaner-scheduleWeekday"), actions: PanelRowActions(
                            adjust: adjustWeekday))
                    }
                    if Self.uses12HourClock {
                        Picker("", selection: scheduleHour12Binding) {
                            ForEach(1...12, id: \.self) { hour in
                                Text(String(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .panelKeyboardRow(keyboardRow("cleaner-scheduleHour"), actions: PanelRowActions(
                            adjust: adjustHour12))
                    } else {
                        Picker("", selection: $scheduleHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .panelKeyboardRow(keyboardRow("cleaner-scheduleHour"), actions: PanelRowActions(
                            adjust: adjustHour24))
                    }
                    Picker("", selection: $scheduleMinute) {
                        ForEach(minuteChoices, id: \.self) { minute in
                            Text(String(format: ":%02d", minute)).tag(minute)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .panelKeyboardRow(keyboardRow("cleaner-scheduleMinute"), actions: PanelRowActions(
                        adjust: adjustMinute))
                    if Self.uses12HourClock {
                        Picker("", selection: schedulePMBinding) {
                            Text(Self.dayPeriodSymbols.am).tag(false)
                            Text(Self.dayPeriodSymbols.pm).tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .panelKeyboardRow(keyboardRow("cleaner-schedulePeriod"), actions: PanelRowActions(
                            adjust: adjustPeriod))
                    }
                    Spacer()
                }
                Toggle(l10n.s.cleanerScheduleNotifyToggle, isOn: $scheduleNotify)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .panelKeyboardRow(keyboardRow("cleaner-scheduleNotify"), actions: PanelRowActions(
                        activate: { scheduleNotify.toggle() }))
                if scheduleNotify, notificationsDenied {
                    Text(l10n.s.cleanerNotifDenied)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(l10n.s.cleanerNotifOpenSettings) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                    .panelKeyboardRow(keyboardRow("cleaner-notificationSettings"), actions: PanelRowActions(activate: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }))
                }
                if let next = scheduler.nextFire {
                    Text(String(format: l10n.s.cleanerScheduleNextFormat,
                                Self.nextRunFormatter.string(from: next)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if lastAutoRun > 0 {
                    Text(lastRunLine)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
        }
    }

    /// The schedule card's reactions, shared by the folded and full forms:
    /// keep the scheduler armed with the latest picks, ask for notification
    /// permission on opt in, and re-read the permission whenever the app
    /// becomes active again (coming back from System Settings included).
    private struct ScheduleChangeSync: ViewModifier {
        @Binding var notify: Bool
        @Binding var frequency: String
        @Binding var hour: Int
        @Binding var minute: Int
        @Binding var weekday: Int
        let refresh: () -> Void

        func body(content: Content) -> some View {
            content
                .onAppear { refresh() }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification)) { _ in
                    refresh()
                }
                .onChange(of: frequency) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: hour) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: minute) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: weekday) { _, _ in CleanerScheduler.shared.syncWithPreferences() }
                .onChange(of: notify) { _, wanted in
                    if wanted { Notifier.requestPermission() }
                    refresh()
                }
        }
    }

    private var lastRunLine: String {
        let ranAt = Self.nextRunFormatter.string(from: Date(timeIntervalSince1970: lastAutoRun))
        if lastAutoFreed > 0 {
            return String(format: l10n.s.cleanerScheduleLastFormat,
                          Self.byteString(Int64(lastAutoFreed)))
        }
        return String(format: l10n.s.cleanerScheduleRanFormat, ranAt)
    }

    /// Checked slightly delayed so a just fired authorization prompt has a
    /// chance to be answered before the warning appears. The notification
    /// center only exists for real app bundles (bare test binaries have
    /// none and would throw).
    private func refreshNotificationStatus() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    notificationsDenied = settings.authorizationStatus == .denied
                }
            }
        }
    }

    // MARK: Busy

    private func busyState(_ message: String, detail: String?) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: compact ? 24 : 0)
            SparkleGlyph(animating: true, size: compact ? 40 : 54)
            Text(message).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: compact ? 24 : 0)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 320)
    }

    // MARK: Results

    private var resultsState: some View {
        VStack(spacing: 0) {
            resultsHeader
            Divider()
            if cleaner.items.isEmpty {
                VStack(spacing: 10) {
                    Spacer(minLength: 24)
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.green)
                    Text(l10n.s.cleanerNothingFound)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        section(l10n.s.cleanerSafeSection, groups: DisplayGroup.allCases.filter(\.isSafe))
                        section(l10n.s.cleanerOptionalSection, groups: DisplayGroup.allCases.filter { !$0.isSafe })
                    }
                    .listStyle(.inset)
                    // Inside the floating panel the list must not paint its own
                    // opaque backdrop over the panel's translucent material.
                    .scrollContentBackground(compact ? .hidden : .automatic)
                    .onChange(of: navigator.focus) { _, focus in
                        guard let id = focusedResultID(focus) else { return }
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .frame(minHeight: compact ? 280 : 0)
                Divider()
                resultsFooter
            }
        }
    }

    private var resultsHeader: some View {
        HStack(spacing: 12) {
            SparkleGlyph(size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.s.cleanerName).font(.system(size: 15, weight: .semibold))
                Text("\(Self.byteString(cleaner.totalSize)) \(l10n.s.uninstallerFoundTitle)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { cleaner.reset() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .panelKeyboardRow(keyboardRow("cleaner-reset"), actions: PanelRowActions(activate: { cleaner.reset() }))
        }
        .padding(compact ? 12 : 16)
    }

    @ViewBuilder
    private func section(_ header: String, groups: [DisplayGroup]) -> some View {
        let visible = groups.filter { !items(for: $0).isEmpty }
        if !visible.isEmpty {
            Section(header) {
                ForEach(visible) { group in groupRow(group) }
            }
        }
    }

    private func groupRow(_ group: DisplayGroup) -> some View {
        let group_items = items(for: group)
        return DisclosureGroup(isExpanded: groupExpandedBinding(group)) {
            if group == .leftovers {
                Text(l10n.s.cleanerLeftoversNote)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            if group == .loginItems {
                Text(l10n.s.cleanerLoginItemsNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(group_items) { item in itemRow(item) }
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: groupBinding(group)).labelsHidden().toggleStyle(.checkbox)
                    .panelKeyboardRow(keyboardRow("cleaner-group-\(group.rawValue)-include"), actions: PanelRowActions(
                        activate: { groupBinding(group).wrappedValue.toggle() }))
                Image(systemName: group.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title(for: group)).font(.system(size: 13, weight: .medium))
                    Text(caption(for: group))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text(Self.byteString(group_items.reduce(0) { $0 + $1.size }))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.vertical, 3)
        }
        .panelKeyboardRow(keyboardRow("cleaner-group-\(group.rawValue)-disclosure"), actions: PanelRowActions(
            activate: { groupExpandedBinding(group).wrappedValue.toggle() },
            adjust: { direction, _ in
                let binding = groupExpandedBinding(group)
                let expanded = direction == .increase
                guard binding.wrappedValue != expanded else { return false }
                binding.wrappedValue = expanded
                return true
            }))
        .id("cleaner-group-\(group.rawValue)")
    }

    private func itemRow(_ item: JunkCleaner.Item) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: includeBinding(item)).labelsHidden().toggleStyle(.checkbox)
                .panelKeyboardRow(keyboardRow("cleaner-item-\(item.id)-include"), actions: PanelRowActions(
                    activate: { includeBinding(item).wrappedValue.toggle() }))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text(prettyPath(item.url))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(Self.byteString(item.size))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.leading, 8)
        .padding(.vertical, 1)
        .contextMenu {
            Button(l10n.s.cleanerRevealInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
        }
        .id("cleaner-item-\(item.id)")
    }

    private func focusedResultID(_ focus: PanelFocusTarget?) -> String? {
        guard compact,
              case .row(let row)? = focus,
              row.section == keyboardSection,
              let localID = row.local as? String else { return nil }
        if let group = DisplayGroup.allCases.first(where: {
            localID == "cleaner-group-\($0.rawValue)-include"
                || localID == "cleaner-group-\($0.rawValue)-disclosure"
        }) {
            return "cleaner-group-\(group.rawValue)"
        }
        return cleaner.items.first { localID == "cleaner-item-\($0.id)-include" }
            .map { "cleaner-item-\($0.id)" }
    }

    private var resultsFooter: some View {
        HStack {
            Text(String(format: l10n.s.uninstallerSelectedFormat,
                        cleaner.selectedCount, cleaner.items.count))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button(l10n.s.uninstallerCancel) { cleaner.reset() }
                .panelKeyboardRow(keyboardRow("cleaner-cancel"), actions: PanelRowActions(activate: { cleaner.reset() }))
            Button(String(format: l10n.s.cleanerCleanSizeFormat,
                          Self.byteString(cleaner.selectedSize))) {
                cleaner.cleanSelected()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(cleaner.selectedCount == 0)
            .panelKeyboardRow(cleaner.selectedCount == 0 ? nil : keyboardRow("cleaner-apply"),
                              actions: PanelRowActions(activate: { cleaner.cleanSelected() }))
        }
        .padding(compact ? 12 : 16)
    }

    // MARK: Done

    private func doneState(freed: Int64, failed: Int) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: compact ? 20 : 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: compact ? 40 : 54))
                .foregroundStyle(.green)
            Text(l10n.s.uninstallerDoneTitle).font(.system(size: compact ? 17 : 20, weight: .bold))
            Text(String(format: l10n.s.uninstallerFreedFormat, Self.byteString(freed)))
                .font(.system(size: 13)).foregroundStyle(.secondary)
            Text(l10n.s.cleanerDoneNote)
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if failed > 0 {
                Text(l10n.s.uninstallerSomeFailed)
                    .font(.caption).foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button(l10n.s.cleanerAgain) { cleaner.reset() }
                .controlSize(.large)
                .padding(.top, 6)
                .panelKeyboardRow(keyboardRow("cleaner-again"), actions: PanelRowActions(activate: { cleaner.reset() }))
            Spacer(minLength: compact ? 20 : 0)
        }
        .padding(compact ? 14 : 28)
        .frame(maxWidth: .infinity, minHeight: compact ? 0 : 320)
    }

    // MARK: Helpers

    private func includeBinding(_ item: JunkCleaner.Item) -> Binding<Bool> {
        Binding(
            get: { cleaner.items.first(where: { $0.id == item.id })?.include ?? false },
            set: { cleaner.setInclude($0, for: item.id) }
        )
    }

    private func groupBinding(_ group: DisplayGroup) -> Binding<Bool> {
        Binding(
            get: {
                let group_items = items(for: group)
                return !group_items.isEmpty && group_items.allSatisfy(\.include)
            },
            set: { include in
                for item in items(for: group) {
                    cleaner.setInclude(include, for: item.id)
                }
            }
        )
    }

    private func keyboardRow(_ localID: String) -> PanelRowID? {
        keyboardSection.map { PanelRowID($0, localID) }
    }

    private func groupExpandedBinding(_ group: DisplayGroup) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(group) },
            set: { expanded in
                if expanded { expandedGroups.insert(group) }
                else { expandedGroups.remove(group) }
            }
        )
    }

    private func toggleScheduleExpanded() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { scheduleExpanded.toggle() }
    }

    private func adjustScheduleDisclosure(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        let expanded = direction == .increase
        guard scheduleExpanded != expanded else { return false }
        toggleScheduleExpanded()
        return true
    }

    private func toggleWhatsAppExpanded() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { whatsAppExpanded.toggle() }
    }

    private func adjustWhatsAppDisclosure(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        let expanded = direction == .increase
        guard whatsAppExpanded != expanded else { return false }
        toggleWhatsAppExpanded()
        return true
    }

    private func adjustFrequency(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        adjust(&scheduleFrequencyRaw, values: CleanerSchedule.Frequency.allCases.map(\.rawValue), direction: direction)
    }

    private func adjustWeekday(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        adjust(&scheduleWeekday, values: Array(1...7), direction: direction)
    }

    private func adjustHour12(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        var hour = scheduleHour12Binding.wrappedValue
        let adjusted = adjust(&hour, values: Array(1...12), direction: direction)
        scheduleHour12Binding.wrappedValue = hour
        return adjusted
    }

    private func adjustHour24(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        adjust(&scheduleHour, values: Array(0..<24), direction: direction)
    }

    private func adjustMinute(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        adjust(&scheduleMinute, values: minuteChoices, direction: direction)
    }

    private func adjustPeriod(_ direction: PanelAdjustDirection, _: Bool) -> Bool {
        let next = direction == .increase
        guard schedulePMBinding.wrappedValue != next else { return false }
        schedulePMBinding.wrappedValue = next
        return true
    }

    private func adjust<Value: Equatable>(_ value: inout Value, values: [Value], direction: PanelAdjustDirection) -> Bool {
        guard let index = values.firstIndex(of: value) else { return false }
        let next = direction == .increase ? index + 1 : index - 1
        guard values.indices.contains(next) else { return false }
        value = values[next]
        return true
    }

    private func prettyPath(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// The cleaner hosted inside the menu panel or the quick panel, with the
/// shared header and close affordance of the other hosted utilities.
struct PanelCleanerView: View {
    @ObservedObject private var l10n = L10n.shared
    var onClose: () -> Void
    /// Set only by the menu-panel host, not the quick launcher.
    var keyboardSection: PanelSectionID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .semibold))
                Text(l10n.s.cleanerName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.menuClose)
                .panelKeyboardRow(keyboardSection.map { PanelRowID($0, "cleaner-close") },
                                  actions: PanelRowActions(activate: onClose))
            }
            CleanerView(compact: true, keyboardSection: keyboardSection)
        }
        .padding(2)
        .onAppear { PanelInteractionState.shared.viewKeepsPopoverOpen = true }
        .onDisappear { PanelInteractionState.shared.viewKeepsPopoverOpen = false }
    }
}
