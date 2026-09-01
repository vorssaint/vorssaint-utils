with open('Sources/Vorssaint/UI/MenuPanel/BKBatteryHeroView.swift', 'r') as f:
    content = f.read()

bad = """    private func peripheralIcon(for kind: PeripheralBatteryDevice.Kind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "magicmouse.fill"
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .gameController: return "gamecontroller"
        case .applePencil: return "applepencil"
        case .watch: return "applewatch"
        case .case: return "airpods.chargingcase"
        case .unknown: return "battery.100"
        }
    }"""

good = """    private func peripheralIcon(for kind: PeripheralBatteryKind) -> String {
        switch kind {
        case .keyboard: return "keyboard"
        case .mouse: return "magicmouse"
        case .trackpad: return "magicmouse.fill"
        case .audio: return "airpods"
        case .device: return "battery.100"
        }
    }"""

content = content.replace(bad, good)

# Also fix the parameter type in the function header from PeripheralBatteryDevice.Kind to PeripheralBatteryKind
with open('Sources/Vorssaint/UI/MenuPanel/BKBatteryHeroView.swift', 'w') as f:
    f.write(content)
