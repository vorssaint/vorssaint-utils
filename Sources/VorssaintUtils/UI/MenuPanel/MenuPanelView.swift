import Combine
import SwiftUI

/// Content of the menu bar popover: keep-awake controls, quick utilities and
/// the system monitor.
struct MenuPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @AppStorage(DefaultsKey.hotkeyEnabled) private var hotkeyEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            KeepAwakeCard()
            UtilitiesSection()
            MixerSection()
            SystemSection()
            footer
        }
        .padding(12)
        .frame(width: 332)
        .onAppear {
            awake.refreshPasswordlessStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandBadge(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppInfo.name)
                    .font(.system(size: 15, weight: .bold))
                Text(awake.isActive ? l10n.s.panelAwake : l10n.s.panelNormalSleep)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if awake.isActive {
                Text(l10n.s.panelActiveBadge)
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.5)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.18)))
                    .foregroundStyle(.green)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                appDelegate()?.openSettingsWindow()
            } label: {
                Label(l10n.s.panelSettings, systemImage: "gearshape")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if hotkeyEnabled {
                Text(l10n.s.panelHotkeyHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label(l10n.s.panelQuit, systemImage: "power")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

// MARK: - Keep awake

struct KeepAwakeCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.s.keepAwakeTitle)
                        .font(.system(size: 13, weight: .semibold))
                    statusLine
                }
                Spacer()
                Toggle("", isOn: activeBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if awake.isActive, awake.endDate != nil {
                HStack(spacing: 6) {
                    extendButton(15)
                    extendButton(30)
                    extendButton(60)
                    Spacer()
                }
            }

            if !awake.isActive {
                HStack {
                    Text(l10n.s.durationLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    DurationPicker(selection: $defaultDuration)
                }
            }

            Divider()

            optionRow(title: l10n.s.keepDisplayOn,
                      caption: nil,
                      isOn: $awake.keepDisplayOn,
                      disabled: false)

            optionRow(title: l10n.s.clamshellTitle,
                      caption: clamshellCaption,
                      isOn: $awake.clamshellPreferred,
                      disabled: false)
        }
        .panelCard()
    }

    private var statusLine: some View {
        Group {
            if awake.isActive {
                if let end = awake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(l10n.s.keepAwakeEndsIn) \(Self.remainingText(until: end))")
                    }
                } else {
                    Text(l10n.s.keepAwakeUntilDisabled)
                }
            } else {
                Text(l10n.s.keepAwakeNormalRules)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var clamshellCaption: String {
        if awake.clamshellActive {
            return l10n.s.clamshellOnCaption
        }
        if awake.clamshellPreferred {
            return l10n.s.clamshellNeedsSession
        }
        return awake.passwordlessClamshell ? l10n.s.clamshellReady : l10n.s.clamshellNeedsPassword
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { awake.isActive },
            set: { on in
                if on {
                    awake.activate(minutes: defaultDuration)
                } else {
                    awake.deactivate(reason: .manual)
                }
            }
        )
    }

    private func optionRow(title: String, caption: String?, isOn: Binding<Bool>, disabled: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(disabled)
        }
    }

    private func extendButton(_ minutes: Int) -> some View {
        Button("+\(minutes) min") {
            awake.extend(minutes: minutes)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: 10))
    }

    private static func remainingText(until end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSinceNow))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }
}

/// Session duration picker shared by the panel and Settings.
struct DurationPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var selection: Int

    var body: some View {
        Picker("", selection: $selection) {
            Text(l10n.s.minutes15).tag(15)
            Text(l10n.s.minutes30).tag(30)
            Text(l10n.s.hour1).tag(60)
            Text(l10n.s.hours2).tag(120)
            Text(l10n.s.hours4).tag(240)
            Text(l10n.s.hours8).tag(480)
            Text(l10n.s.indefinite).tag(0)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

// MARK: - Utilities

struct UtilitiesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var desktopHidden = false
    @State private var hiddenFilesShown = false
    @State private var confirmTrash = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.s.utilitiesSection)
            VStack(spacing: 8) {
                toggleRow(icon: "eye.slash",
                          title: l10n.s.hideDesktopIcons,
                          isOn: Binding(
                            get: { desktopHidden },
                            set: { value in
                                desktopHidden = value
                                DispatchQueue.global(qos: .userInitiated).async {
                                    FinderTweaks.setDesktopIconsHidden(value)
                                }
                            }))
                toggleRow(icon: "doc.text.magnifyingglass",
                          title: l10n.s.showHiddenFiles,
                          isOn: Binding(
                            get: { hiddenFilesShown },
                            set: { value in
                                hiddenFilesShown = value
                                DispatchQueue.global(qos: .userInitiated).async {
                                    FinderTweaks.setHiddenFilesShown(value)
                                }
                            }))

                Divider()

                HStack(spacing: 8) {
                    actionButton(icon: "display", title: l10n.s.turnOffDisplay) {
                        appDelegate()?.closePopover()
                        QuickActions.turnOffDisplay()
                    }
                    actionButton(icon: "eject.fill", title: l10n.s.ejectDisks) {
                        appDelegate()?.closePopover()
                        QuickActions.ejectAllDisks { ok, message in
                            if !ok {
                                Notifier.post(title: l10n.s.ejectDisks,
                                              body: message ?? l10n.s.ejectFailed)
                            }
                        }
                    }
                }
                actionButton(icon: "trash",
                             title: confirmTrash ? l10n.s.confirmQuestion : l10n.s.emptyTrash,
                             destructive: confirmTrash) {
                    if confirmTrash {
                        confirmTrash = false
                        appDelegate()?.closePopover()
                        QuickActions.emptyTrash { ok, message in
                            if !ok {
                                Notifier.post(title: l10n.s.emptyTrash,
                                              body: message ?? l10n.s.trashFailed)
                            }
                        }
                    } else {
                        confirmTrash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            confirmTrash = false
                        }
                    }
                }
            }
            .panelCard()
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let desktop = FinderTweaks.desktopIconsHidden()
                let hidden = FinderTweaks.hiddenFilesShown()
                DispatchQueue.main.async {
                    desktopHidden = desktop
                    hiddenFilesShown = hidden
                }
            }
        }
    }

    private func toggleRow(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private func actionButton(icon: String, title: String, destructive: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .foregroundStyle(destructive ? Color.red : Color.primary)
    }
}
