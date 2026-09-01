import AppKit
import Combine
import Foundation

final class InactiveAppService: ObservableObject {
    static let shared = InactiveAppService()

    @Published private(set) var exceptions: [String] = []
    
    private var lastActiveTimes: [pid_t: Date] = [:]
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        loadExceptions()
        syncWithPreferences()
    }
    
    func syncWithPreferences() {
        if UserDefaults.standard.bool(forKey: DefaultsKey.inactiveAppsEnabled) {
            start()
        } else {
            stop()
        }
    }
    
    private func start() {
        guard timer == nil else { return }
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didActivateApp(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didTerminateApp(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        // Populate current frontmost
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            lastActiveTimes[frontmost.processIdentifier] = Date()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkIdleApps()
        }
    }
    
    private func stop() {
        timer?.invalidate()
        timer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        lastActiveTimes.removeAll()
    }
    
    @objc private func didActivateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        lastActiveTimes[app.processIdentifier] = Date()
    }
    
    @objc private func didTerminateApp(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        lastActiveTimes.removeValue(forKey: app.processIdentifier)
    }
    
    private func checkIdleApps() {
        let idleMinutes = UserDefaults.standard.integer(forKey: DefaultsKey.inactiveAppsIdleMinutes)
        let threshold = Date().addingTimeInterval(-Double(idleMinutes * 60))
        let memoryFloor = UserDefaults.standard.integer(forKey: DefaultsKey.inactiveAppsMemoryFloorMB)
        let autoQuit = UserDefaults.standard.bool(forKey: DefaultsKey.inactiveAppsAutoQuit)
        
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard app.activationPolicy == .regular else { continue }
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // Exclusions
            if exceptions.contains(bundleID) { continue }
            if isMandatoryException(bundleID) { continue }
            if app.isActive { continue }
            
            let lastActive = lastActiveTimes[app.processIdentifier] ?? app.launchDate ?? Date()
            if lastActive < threshold {
                let pid = app.processIdentifier
                
                let usage = ProcessUsageService.shared.snapshot.processes.first(where: { $0.pid == pid })
                let memoryMB = (usage?.memoryBytes ?? 0) / (1024 * 1024)
                
                if memoryMB >= memoryFloor {
                    if autoQuit {
                        app.terminate()
                    } else {
                        // To avoid spam, we reset the lastActive time!
                        lastActiveTimes[pid] = Date()
                        Notifier.postInactiveApp(appName: app.localizedName ?? "App", bundleID: bundleID, memoryMB: memoryMB)
                    }
                }
            }
        }
    }
    
    // MARK: - Exceptions
    
    func addException(_ bundleID: String) {
        if !exceptions.contains(bundleID) {
            exceptions.append(bundleID)
            saveExceptions()
        }
    }
    
    func removeException(_ bundleID: String) {
        exceptions.removeAll { $0 == bundleID }
        saveExceptions()
    }
    
    func isMandatoryException(_ bundleID: String) -> Bool {
        bundleID == Bundle.main.bundleIdentifier
    }
    
    private func loadExceptions() {
        exceptions = UserDefaults.standard.stringArray(forKey: DefaultsKey.inactiveAppsExceptions) ?? []
    }
    
    private func saveExceptions() {
        UserDefaults.standard.set(exceptions, forKey: DefaultsKey.inactiveAppsExceptions)
    }
}
