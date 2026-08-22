// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit.pwr_mgt

enum CPUPowerMode: String, CaseIterable, Identifiable {
    case lowPower = "lowPower"
    case balanced = "balanced"
    case maximum = "maximum"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lowPower: return "Baixo (Eco)"
        case .balanced: return "Médio (Padrão)"
        case .maximum: return "Máximo (Turbo)"
        }
    }

    var description: String {
        switch self {
        case .lowPower:
            return "Limita o consumo da CPU para economia máxima de bateria e menor aquecimento."
        case .balanced:
            return "Gerenciamento dinâmico padrão do macOS equilibrando energia e velocidade."
        case .maximum:
            return "Alto desempenho contínuo sem throttling para cargas de trabalho pesadas."
        }
    }

    var iconName: String {
        switch self {
        case .lowPower: return "leaf.fill"
        case .balanced: return "bolt.fill"
        case .maximum: return "flame.fill"
        }
    }
}

final class ProcessorPowerModeService: ObservableObject {
    static let shared = ProcessorPowerModeService()

    @Published private(set) var currentMode: CPUPowerMode = .balanced
    @Published private(set) var isWorking = false
    @Published private(set) var isPurgingMemory = false
    @Published var autoSwitchingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoSwitchingEnabled, forKey: DefaultsKey.autoPowerModeEnabled)
        }
    }

    private var performanceAssertionID: IOPMAssertionID = 0
    private let queue = DispatchQueue(label: "com.vorssaint.processor-power", qos: .userInitiated)
    private var batteryTimer: Timer?

    private init() {
        self.autoSwitchingEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.autoPowerModeEnabled)
        refreshState()
        startBatteryObservation()
    }

    func syncWithPreferences() {
        let savedRaw = UserDefaults.standard.string(forKey: DefaultsKey.processorPowerMode) ?? CPUPowerMode.balanced.rawValue
        if let mode = CPUPowerMode(rawValue: savedRaw) {
            setMode(mode, savePreference: false)
        }
    }

    func toggleNextMode() {
        let next: CPUPowerMode
        switch currentMode {
        case .lowPower: next = .balanced
        case .balanced: next = .maximum
        case .maximum: next = .lowPower
        }
        setMode(next)
    }

    func purgeMemory(completion: ((Bool) -> Void)? = nil) {
        guard !isPurgingMemory else {
            completion?(false)
            return
        }

        isPurgingMemory = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)

        queue.async {
            var ok = Sudoers.purgeMemory()
            if !ok {
                _ = AdminShell.runSync("/usr/sbin/purge", prompt: "O Vorssaint precisa de autorização para liberar memória RAM inativa.")
                ok = true
            }

            DispatchQueue.main.async {
                self.isPurgingMemory = false
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                SystemMonitor.shared.refresh()
                completion?(ok)
            }
        }
    }

    func refreshState() {
        queue.async {
            var isLowPower = false
            if #available(macOS 12.0, *) {
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            if !isLowPower {
                let report = Shell.run("/usr/bin/pmset", ["-g"])
                if report.output.contains("lowpowermode        1") || report.output.contains("lowpowermode 1") {
                    isLowPower = true
                }
            }

            let saved = UserDefaults.standard.string(forKey: DefaultsKey.processorPowerMode) ?? CPUPowerMode.balanced.rawValue
            let resolved: CPUPowerMode
            if isLowPower {
                resolved = .lowPower
            } else if saved == CPUPowerMode.maximum.rawValue {
                resolved = .maximum
            } else {
                resolved = .balanced
            }

            DispatchQueue.main.async {
                self.currentMode = resolved
            }
        }
    }

    func setMode(_ mode: CPUPowerMode, savePreference: Bool = true, completion: ((Bool) -> Void)? = nil) {
        guard !isWorking else {
            completion?(false)
            return
        }

        if savePreference {
            UserDefaults.standard.set(mode.rawValue, forKey: DefaultsKey.processorPowerMode)
        }

        isWorking = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        queue.async {
            var success = false

            switch mode {
            case .lowPower:
                self.releasePerformanceAssertion()
                success = Sudoers.pmsetLowPowerMode(true)
                if !success {
                    _ = AdminShell.runSync("pmset -a lowpowermode 1", prompt: "O Vorssaint precisa de autorização para ativar o Modo de Economia de Energia.")
                    success = true
                }

            case .balanced:
                self.releasePerformanceAssertion()
                success = Sudoers.pmsetLowPowerMode(false)
                if !success {
                    _ = AdminShell.runSync("pmset -a lowpowermode 0", prompt: "O Vorssaint precisa de autorização para desativar o Modo de Economia de Energia.")
                    success = true
                }

            case .maximum:
                _ = Sudoers.pmsetLowPowerMode(false)
                self.acquirePerformanceAssertion()
                success = true
            }

            DispatchQueue.main.async {
                self.isWorking = false
                self.currentMode = mode
                completion?(success)
            }
        }
    }

    private func startBatteryObservation() {
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkBatteryAutomation()
        }
    }

    private func checkBatteryAutomation() {
        guard autoSwitchingEnabled else { return }
        let snapshot = SystemMonitor.shared.snapshot
        guard let power = snapshot.power, let percent = power.chargePercent else { return }

        // When charge <= 20% on battery and not in low power, switch to low power
        if !power.externalConnected, percent <= 20, currentMode != .lowPower {
            setMode(.lowPower, savePreference: false)
        } else if power.externalConnected, currentMode == .lowPower {
            // When plugged back into power, restore to balanced
            setMode(.balanced, savePreference: false)
        }
    }

    private func acquirePerformanceAssertion() {
        guard performanceAssertionID == 0 else { return }
        var id: IOPMAssertionID = 0
        let reason = "Vorssaint CPU Maximum Performance" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )
        if result == kIOReturnSuccess {
            performanceAssertionID = id
        }
    }

    private func releasePerformanceAssertion() {
        guard performanceAssertionID != 0 else { return }
        IOPMAssertionRelease(performanceAssertionID)
        performanceAssertionID = 0
    }
}
