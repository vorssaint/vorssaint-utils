// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A compact summary matching the duration control, with a clock grid
/// for pointer input. The native field also supports arbitrary minute values.
struct KeepAwakeEndTimePicker: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var selection: Date
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Button { isPresented.toggle() } label: {
                HStack(spacing: 6) {
                    Text(selection, style: .time)
                        .font(.system(size: 11))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(l10n.s.keepAwakeUntilLabel)
            .accessibilityValue(selection.formatted(date: .omitted, time: .shortened))
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                editor
            }

            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(endSummary(now: context.date))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.s.keepAwakeUntilLabel)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                DatePicker(l10n.s.keepAwakeUntilLabel, selection: $selection,
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .controlSize(.small)
                    .labelsHidden()
                    .fixedSize()
            }

            timeGrid(title: labels.hour, component: .hour, values: Array(0..<24))
            Divider()
            timeGrid(title: labels.minute, component: .minute, values: Array(stride(from: 0, to: 60, by: 5)))
        }
        .padding(10)
        .frame(width: 224)
    }

    private func timeGrid(title: String, component: Calendar.Component, values: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 6), spacing: 3) {
                ForEach(values, id: \.self) { value in
                    let selected = Calendar.current.component(component, from: selection) == value
                    Button {
                        // Edit on a neutral date: the session resolves the next
                        // occurrence at activation, including a DST transition.
                        var parts = Calendar.current.dateComponents([.hour, .minute], from: selection)
                        parts.setValue(value, for: component)
                        parts.year = 2001
                        parts.month = 1
                        parts.day = 15
                        if let date = Calendar.current.date(from: parts) { selection = date }
                    } label: {
                        Text(String(format: "%02d", value))
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 22)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color.primary.opacity(0.05),
                                        in: RoundedRectangle(cornerRadius: 4))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(value)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private func endSummary(now: Date) -> String {
        let end = KeepAwakeAutomationSupport.resolvedUntilDate(picked: selection, now: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: l10n.language.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: end)
    }

    private var labels: (hour: String, minute: String) {
        switch l10n.language {
        case .enUS: return ("Hour (0–23)", "Minute")
        case .ptBR: return ("Hora (0–23)", "Minuto")
        case .tr: return ("Saat (0–23)", "Dakika")
        case .ru: return ("Час (0–23)", "Минута")
        case .es: return ("Hora (0–23)", "Minuto")
        case .de: return ("Stunde (0–23)", "Minute")
        case .fr: return ("Heure (0–23)", "Minute")
        case .it: return ("Ora (0–23)", "Minuto")
        case .ja: return ("時 (0–23)", "分")
        case .ko: return ("시 (0–23)", "분")
        case .zhHans: return ("小时 (0–23)", "分钟")
        case .zhTW, .zhHK: return ("小時 (0–23)", "分鐘")
        case .ar: return ("الساعة (0–23)", "الدقيقة")
        }
    }
}
