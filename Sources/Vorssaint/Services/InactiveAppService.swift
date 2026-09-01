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
            
            if exceptions.contains(bundleID) { continue }
            if isMandatoryException(bundleID) { continue }
            if app.isActive { continue }
            
            let lastActive = lastActiveTimes[app.processIdentifier] ?? app.launchDate ?? Date()
            if lastActive < threshold {
                let pid = app.processIdentifier
                
                let footprint = InactiveAppService.physicalFootprint(of: pid) ?? 0
                let memoryMB = Int(footprint / (1024 * 1024))
                
                if memoryMB >= memoryFloor {
                    if autoQuit {
                        app.terminate()
                    } else {
                        lastActiveTimes[pid] = Date()
                        Notifier.postInactiveApp(appName: app.localizedName ?? "App", bundleID: bundleID, memoryMB: memoryMB)
                    }
                }
            }
        }
    }
    
    private static func physicalFootprint(of pid: pid_t) -> Double? {
        var info = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
            }
        }
        guard status == 0, info.ri_phys_footprint > 0 else { return nil }
        return Double(info.ri_phys_footprint)
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
