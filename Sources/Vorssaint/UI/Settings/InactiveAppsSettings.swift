import SwiftUI

struct InactiveAppsSettings: View {
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = InactiveAppService.shared
    
    @AppStorage(DefaultsKey.inactiveAppsEnabled) private var enabled = false
    @AppStorage(DefaultsKey.inactiveAppsAutoQuit) private var autoQuit = false
    @AppStorage(DefaultsKey.inactiveAppsIdleMinutes) private var idleMinutes = 60
    @AppStorage(DefaultsKey.inactiveAppsMemoryFloorMB) private var memoryFloorMB = 500
    
    @State private var showingAppPicker = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Inactive App Monitor", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        InactiveAppService.shared.syncWithPreferences()
                    }
                Text("Monitors background applications and notifies you if they have been idle for too long while consuming significant memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Thresholds") {
                HStack {
                    Text("Idle Time")
                    Spacer()
                    Picker("", selection: $idleMinutes) {
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("2 hours").tag(120)
                    }
                    .frame(width: 120)
                }
                
                HStack {
                    Text("Memory Threshold")
                    Spacer()
                    Picker("", selection: $memoryFloorMB) {
                        Text("250 MB").tag(250)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1000)
                        Text("2 GB").tag(2000)
                    }
                    .frame(width: 120)
                }
                
                Toggle("Auto-Quit Without Asking", isOn: $autoQuit)
            }
            .disabled(!enabled)

            Section("Exceptions") {
                if sortedExceptions.isEmpty {
                    Text("No exceptions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedExceptions, id: \.self) { bundleID in
                        HStack(spacing: 9) {
                            Image(nsImage: InstalledApps.icon(for: bundleID))
                                .resizable().frame(width: 20, height: 20)
                            Text(InstalledApps.name(for: bundleID))
                            Spacer()
                            if service.isMandatoryException(bundleID) {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Button {
                                    service.removeException(bundleID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .disabled(!enabled)
                }

                Button {
                    showingAppPicker = true
                } label: {
                    Label("Add Application", systemImage: "plus")
                }
                .disabled(!enabled)
            }

            if enabled, !permissions.notifications {
                Section("Permission Required") {
                    PermissionRow(kind: .notifications)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAppPicker) {
            appPickerSheet
        }
    }

    private var sortedExceptions: [String] {
        service.exceptions.sorted { InstalledApps.name(for: $0).localizedCaseInsensitiveCompare(InstalledApps.name(for: $1)) == .orderedAscending }
    }

    private var appPickerSheet: some View {
        let excluded = Set(service.exceptions)
        return AppPickerView {
            showingAppPicker = false
        } onSelect: { url in
            showingAppPicker = false
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            service.addException(bundleID)
        } loadApps: {
            InstalledApps.installedBundleApplications(excluding: excluded)
        }
    }
}
