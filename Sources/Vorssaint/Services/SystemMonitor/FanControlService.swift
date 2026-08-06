// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FanStatus: Identifiable {
    var id: Int
    var name: String
    var actualSpeed: Double
    var minSpeed: Double
    var maxSpeed: Double
    var targetSpeed: Double
    var isManual: Bool
}

final class FanControlService: ObservableObject {
    @Published var fans: [FanStatus] = []
    
    private let smc: SMCClient?
    private var fanCount: Int = 0
    
    init(smc: SMCClient?) {
        self.smc = smc
        refresh()
    }
    
    func refresh() {
        guard let smc = smc else { return }
        
        if let fNumKey = smc.key(named: "FNum"), let num = smc.readValue(fNumKey) {
            fanCount = Int(num)
        } else {
            fanCount = 0
        }
        
        var currentFans: [FanStatus] = []
        
        for i in 0..<fanCount {
            let actualKey = smc.key(named: "F\(i)Ac")
            let minKey = smc.key(named: "F\(i)Mn")
            let maxKey = smc.key(named: "F\(i)Mx")
            let targetKey = smc.key(named: "F\(i)Tg")
            let modeKey = smc.key(named: "F\(i)Md")
            
            let actual: Double = actualKey.flatMap { smc.readValue($0) } ?? 0
            let minS: Double = minKey.flatMap { smc.readValue($0) } ?? 0
            let maxS: Double = maxKey.flatMap { smc.readValue($0) } ?? 1000
            let target: Double = targetKey.flatMap { smc.readValue($0) } ?? 0
            let mode: Double = modeKey.flatMap { smc.readValue($0) } ?? 0
            
            currentFans.append(FanStatus(
                id: i,
                name: "Fan \(i + 1)",
                actualSpeed: actual,
                minSpeed: minS,
                maxSpeed: maxS,
                targetSpeed: target,
                isManual: mode == 1
            ))
        }
        
        DispatchQueue.main.async {
            self.fans = currentFans
        }
    }
    
    func setManualMode(for fanId: Int, manual: Bool) {
        guard let smc = smc, let modeKey = smc.key(named: "F\(fanId)Md") else { return }
        let bytes: [UInt8] = [manual ? 1 : 0]
        _ = smc.writeValue(modeKey, bytes: bytes)
        refresh()
    }
    
    func setTargetSpeed(for fanId: Int, speed: Double) {
        guard let smc = smc, let targetKey = smc.key(named: "F\(fanId)Tg") else { return }
        // fpe2 encoding (14 int, 2 frac -> * 4.0)
        let raw = UInt16(speed * 4.0)
        let bytes: [UInt8] = [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        _ = smc.writeValue(targetKey, bytes: bytes)
        refresh()
    }
}
