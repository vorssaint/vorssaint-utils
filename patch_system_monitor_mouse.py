with open('Sources/Vorssaint/Services/SystemMonitor/SystemMonitor.swift', 'r') as f:
    content = f.read()

notify = """
                let oldPeripherals = self.snapshot.peripheralBatteries
                let newPeripherals = next.peripheralBatteries
                
                for newDevice in newPeripherals {
                    if !oldPeripherals.contains(where: { $0.id == newDevice.id }) {
                        if newDevice.kind == .mouse {
                            Notifier.post(title: "Mouse Connected", body: "\\(newDevice.name) is at \\(newDevice.percent)%.")
                        }
                    }
                }
"""

content = content.replace('                if sampledAnything || planChanged {\n                    self.snapshot = next', notify + '\n                if sampledAnything || planChanged {\n                    self.snapshot = next')

with open('Sources/Vorssaint/Services/SystemMonitor/SystemMonitor.swift', 'w') as f:
    f.write(content)
