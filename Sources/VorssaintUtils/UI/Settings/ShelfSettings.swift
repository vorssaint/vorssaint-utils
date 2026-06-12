import SwiftUI

struct ShelfSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.shelfEnabled) private var enabled = false
    @AppStorage(DefaultsKey.shelfShakeToOpen) private var shake = true

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.shelfEnable, isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        ShelfService.shared.syncWithPreferences()
                    }
                Text(l10n.s.shelfEnableCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(l10n.s.shelfNoPermission, systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l10n.s.shelfHowTitle) {
                bullet("1", l10n.s.shelfStep1)
                bullet("2", l10n.s.shelfStep2)
                bullet("3", l10n.s.shelfStep3)
            }

            if enabled {
                Section {
                    HStack {
                        Text(l10n.s.shelfHotkeyLabel)
                        Spacer()
                        ShortcutCaps(keys: ["⌃", "⌥", "⌘", "D"])
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(l10n.s.shelfShakeToggle, isOn: $shake)
                            .onChange(of: shake) { _, _ in
                                ShelfService.shared.syncShakeMonitor()
                            }
                        Text(l10n.s.shelfShakeCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        ShelfService.shared.summon()
                    } label: {
                        Label(l10n.s.shelfOpenNow, systemImage: "tray.and.arrow.down")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
