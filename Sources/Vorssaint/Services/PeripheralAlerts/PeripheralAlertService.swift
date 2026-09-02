import Foundation
import Combine

final class PeripheralAlertService {
    static let shared = PeripheralAlertService()
    private var cancellables = Set<AnyCancellable>()
    private var alertedLowBattery: Set<String> = []
    
    private init() {}
    
    func start() {
        SystemMonitor.shared.$snapshot
            .map { $0.peripheralBatteries }
            .removeDuplicates()
            .sink { [weak self] peripherals in
                self?.checkLowBattery(peripherals)
            }
            .store(in: &cancellables)
    }
    
    private func checkLowBattery(_ peripherals: [PeripheralBatteryDevice]) {
        for device in peripherals {
            let threshold = 20
            if device.percent < threshold {
                if !alertedLowBattery.contains(device.id) {
                    alertedLowBattery.insert(device.id)
                    Notifier.post(title: "Low Battery", body: "\(device.name) is at \(device.percent)%.")
                }
            } else {
                // If it charges back up, remove from alerted list
                alertedLowBattery.remove(device.id)
            }
        }
    }
}
