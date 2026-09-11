// SPDX-License-Identifier: GPL-3.0-or-later

import EventKit
import SwiftUI

struct CalendarSettings: View {
    @ObservedObject private var service = CalendarService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.calendarEnabled) private var enabled = false
    @AppStorage(DefaultsKey.calendarIconStyle) private var iconStyle = CalendarIconStyle.icon.rawValue
    @AppStorage(DefaultsKey.calendarMenuBarComponents) private var menuBarComponentsRaw = "icon"
    @AppStorage(DefaultsKey.calendarTextScale) private var textScale = 1.0
    @AppStorage(DefaultsKey.calendarAlertEnabled) private var alertsEnabled = true
    @AppStorage(DefaultsKey.calendarAlertMinutesBefore) private var alertMinutes = 5
    @AppStorage(DefaultsKey.calendarDateDisplayFormat) private var dateFormat = CalendarDateDisplayFormat.dayMonth.rawValue
    @AppStorage(DefaultsKey.calendarCustomDateFormat) private var customDateFormat = "dd/MM"
    @AppStorage(DefaultsKey.calendarShowMonthOutline) private var showMonthOutline = true
    @AppStorage(DefaultsKey.calendarShowAdjacentMonthDays) private var showAdjacentMonthDays = false
    @AppStorage(DefaultsKey.calendarShowLunarDate) private var showLunarDate = false
    @AppStorage(DefaultsKey.calendarShowWeekNumbers) private var showWeekNumbers = false
    @AppStorage(DefaultsKey.calendarShowWeekends) private var showWeekends = true
    @AppStorage(DefaultsKey.calendarShowDeclinedEvents) private var showDeclinedEvents = false
    @AppStorage(DefaultsKey.calendarEventDots) private var eventDots = CalendarEventDots.multiple.rawValue
    @AppStorage(DefaultsKey.calendarPreserveSelectedDate) private var preserveSelectedDate = true
    @AppStorage(DefaultsKey.calendarShowPastEvents) private var showPastEvents = true
    @AppStorage(DefaultsKey.calendarAlertSound) private var alertSound = true
    @AppStorage(DefaultsKey.calendarAlertFlash) private var alertFlash = false
    private var strings: CalendarStrings { CalendarStrings.current(l10n.language) }

    var body: some View {
        Form {
            Section(strings.title) {
                Toggle(strings.showInMenuBar, isOn: $enabled).onChange(of: enabled) { _, _ in CalendarService.shared.syncWithPreferences() }
                if service.authorizationStatus != .fullAccess { HStack { Text(strings.accessRequired); Spacer(); Button(strings.openPreferences) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!) } } }
            }
            Section(strings.appearance) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(strings.menuBarComponents)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(CalendarMenuBarComponent.allCases) { component in
                        componentRow(component)
                    }
                    if selectedMenuBarComponents.contains(.date) {
                        Picker(strings.menuBarDateFormat, selection: $dateFormat) {
                            Text("Sistema").tag(CalendarDateDisplayFormat.system.rawValue)
                            Text("dd/MM").tag(CalendarDateDisplayFormat.dayMonth.rawValue)
                            Text("semana, dia").tag(CalendarDateDisplayFormat.weekdayDay.rawValue)
                            Text("mês dia").tag(CalendarDateDisplayFormat.monthDay.rawValue)
                            Text("Personalizado").tag(CalendarDateDisplayFormat.custom.rawValue)
                        }
                        .padding(.leading, 22)
                        if dateFormat == CalendarDateDisplayFormat.custom.rawValue {
                            TextField(strings.customDatePattern, text: $customDateFormat)
                                .textFieldStyle(.roundedBorder)
                                .padding(.leading, 22)
                        }
                    }
                }
                Slider(value: $textScale, in: 0.8...1.4, step: 0.1) { Text(strings.textScale) }.onChange(of: textScale) { _, _ in service.refresh() }
            }
            Section(strings.meetingAlerts) {
                Toggle(strings.alerts, isOn: $alertsEnabled).onChange(of: alertsEnabled) { _, active in if active { CalendarAlertScheduler().requestPermission { _ in CalendarService.shared.refresh() } } else { CalendarAlertScheduler().cancelAllAlerts() } }
                Picker(strings.notifyBefore, selection: $alertMinutes) { Text("5 minutos").tag(5); Text("10 minutos").tag(10); Text("15 minutos").tag(15); Text("30 minutos").tag(30); Text("1 hora").tag(60) }
                Toggle("Tocar som", isOn: $alertSound)
                Toggle("Piscar o item da barra", isOn: $alertFlash)
            }
            Section(strings.agenda) {
                Toggle(strings.showMonthOutline, isOn: $showMonthOutline)
                Toggle(strings.showAdjacentDays, isOn: $showAdjacentMonthDays)
                Toggle("Mostrar data lunar", isOn: $showLunarDate)
                Toggle("Mostrar números das semanas", isOn: $showWeekNumbers)
                Toggle("Mostrar fins de semana", isOn: $showWeekends)
                Picker(strings.eventDots, selection: $eventDots) {
                    Text(strings.eventDotsNone).tag(CalendarEventDots.none.rawValue)
                    Text(strings.eventDotsSingleNeutral).tag(CalendarEventDots.singleNeutral.rawValue)
                    Text(strings.eventDotsSingleHighlighted).tag(CalendarEventDots.singleHighlighted.rawValue)
                    Text(strings.eventDotsMultiple).tag(CalendarEventDots.multiple.rawValue)
                }
                Toggle(strings.showDeclinedEvents, isOn: $showDeclinedEvents)
                Toggle("Preservar a data selecionada ao fechar", isOn: $preserveSelectedDate)
                Toggle("Mostrar eventos passados", isOn: $showPastEvents)
                Text("A previsão do tempo não é exibida: o Calendar mantém seus dados locais e não consulta serviços externos.").font(.caption).foregroundStyle(.secondary)
            }
            if service.authorizationStatus == .fullAccess { Section(strings.calendars) { ForEach(service.calendars, id: \.calendarIdentifier) { calendar in Toggle(isOn: binding(for: calendar)) { Label(calendar.title, systemImage: "calendar") } } } }
        }
        .formStyle(.grouped)
        .navigationTitle(strings.title)
        .onAppear {
            migrateLegacyMenuBarStyleIfNeeded()
            service.syncWithPreferences()
        }
        .onChange(of: menuBarComponentsRaw) { _, _ in service.refresh() }
        .onChange(of: dateFormat) { _, _ in service.refresh() }
        .onChange(of: customDateFormat) { _, _ in service.refresh() }
        .onChange(of: alertMinutes) { _, _ in service.refresh() }
        .onChange(of: alertSound) { _, _ in service.refresh() }
        .onChange(of: showDeclinedEvents) { _, _ in service.refresh() }
        .onChange(of: eventDots) { _, _ in service.refresh() }
        .onChange(of: showMonthOutline) { _, _ in service.refresh() }
    }

    private var selectedMenuBarComponents: [CalendarMenuBarComponent] {
        CalendarSupport.menuBarComponents(from: menuBarComponentsRaw, fallbackStyle: CalendarIconStyle(rawValue: iconStyle) ?? .icon)
    }

    private func migrateLegacyMenuBarStyleIfNeeded() {
        guard UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[DefaultsKey.calendarMenuBarComponents] == nil else { return }
        guard let legacyStyle = CalendarIconStyle(rawValue: iconStyle), legacyStyle != .icon else { return }
        menuBarComponentsRaw = legacyStyle.rawValue
    }

    private func updateMenuBarComponents(_ components: [CalendarMenuBarComponent]) {
        menuBarComponentsRaw = CalendarSupport.encodedMenuBarComponents(components)
        iconStyle = components.first?.rawValue ?? CalendarIconStyle.icon.rawValue
    }

    private func componentRow(_ component: CalendarMenuBarComponent) -> some View {
        let selected = selectedMenuBarComponents.contains(component)
        let index = selectedMenuBarComponents.firstIndex(of: component).map { $0 + 1 }
        return HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { selected },
                set: { include in setComponent(component, included: include) }
            )) {
                HStack(spacing: 8) {
                    if let index {
                        Text("\(index)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                    } else {
                        Text(" ")
                            .frame(width: 16)
                    }
                    Text(label(for: component))
                }
            }
            .toggleStyle(.switch)
            Spacer(minLength: 8)
            if selected {
                Button(action: { move(component, by: -1) }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help(strings.moveUp)
                .disabled(index == 1)
                Button(action: { move(component, by: 1) }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .help(strings.moveDown)
                .disabled(index == selectedMenuBarComponents.count)
            }
        }
    }

    private func label(for component: CalendarMenuBarComponent) -> String {
        let strings = CalendarStrings.current(l10n.language)
        switch component {
        case .icon: return strings.componentIcon
        case .date: return strings.componentDate
        case .nextEvent: return strings.componentNextEvent
        }
    }

    private func setComponent(_ component: CalendarMenuBarComponent, included: Bool) {
        var components = selectedMenuBarComponents
        if included {
            guard !components.contains(component) else { return }
            components.append(component)
        } else {
            components.removeAll { $0 == component }
            if components.isEmpty { components = [.icon] }
        }
        updateMenuBarComponents(components)
    }

    private func move(_ component: CalendarMenuBarComponent, by offset: Int) {
        var components = selectedMenuBarComponents
        guard let index = components.firstIndex(of: component) else { return }
        let target = index + offset
        guard components.indices.contains(target) else { return }
        components.swapAt(index, target)
        updateMenuBarComponents(components)
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> { Binding { CalendarSupport.selectedCalendarIDs(from: UserDefaults.standard.data(forKey: DefaultsKey.calendarSelectedCalendars))?.contains(calendar.calendarIdentifier) ?? true } set: { include in var ids = CalendarSupport.selectedCalendarIDs(from: UserDefaults.standard.data(forKey: DefaultsKey.calendarSelectedCalendars)) ?? Set(service.calendars.map(\.calendarIdentifier)); if include { ids.insert(calendar.calendarIdentifier) } else { ids.remove(calendar.calendarIdentifier) }; service.setSelectedCalendars(ids) } }
}
