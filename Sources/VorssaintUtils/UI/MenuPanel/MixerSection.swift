import SwiftUI

/// Per-app volume sliders — the mixer macOS never shipped. Shows every app
/// currently producing sound; dragging below 100% routes that app through a
/// gain stage, and 100% restores untouched passthrough.
struct MixerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.s.mixerSection)
            VStack(alignment: .leading, spacing: 8) {
                if !AppVolumeMixer.isSupported {
                    emptyLabel(l10n.s.mixerUnavailable)
                } else if mixer.needsPermission {
                    permissionHint
                } else if mixer.apps.isEmpty {
                    emptyLabel(l10n.s.mixerEmpty)
                } else {
                    ForEach(mixer.apps) { app in
                        MixerRow(app: app)
                    }
                }
            }
            .panelCard()
        }
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }

    private var permissionHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.s.mixerPermissionBody)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(l10n.s.permissionOpenSettings) {
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
        }
    }
}

private struct MixerRow: View {
    @ObservedObject private var mixer = AppVolumeMixer.shared
    let app: MixerApp

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: ResponsibleProcess.icon(for: app.ownerPid))
                .resizable()
                .frame(width: 18, height: 18)

            Text(app.name)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 86, alignment: .leading)

            Slider(value: volumeBinding, in: 0...1)
                .controlSize(.small)

            Text("\(Int((app.volume * 100).rounded()))%")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)

            Button {
                mixer.toggleMute(app)
            } label: {
                Image(systemName: app.volume <= 0.001 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(app.volume <= 0.001 ? Color.red : Color.secondary)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { app.volume },
            set: { mixer.setVolume($0, for: app) }
        )
    }
}
