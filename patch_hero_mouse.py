with open('Sources/Vorssaint/UI/MenuPanel/BKBatteryHeroView.swift', 'r') as f:
    content = f.read()

mouse_ui = """                let label = statusLabel
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.3), value: label)
                }
                
                let peripherals = SystemMonitor.shared.snapshot.peripheralBatteries
                if !peripherals.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(PeripheralBatterySupport.sorted(peripherals)) { device in
                        HStack(spacing: 8) {
                            Image(systemName: peripheralIcon(for: device.kind))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 10)
                            Text(device.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\\(device.percent)%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(device.percent < 20 ? Color.red : .primary)
                        }
                    }
                }
            }
            
    private func peripheralIcon(for kind: PeripheralBatteryDevice.Kind) -> String {
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

content = content.replace("""                let label = statusLabel
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.3), value: label)
                }
                
                let peripherals = SystemMonitor.shared.snapshot.peripheralBatteries
                if !peripherals.isEmpty {
                    Divider().padding(.vertical, 4)
                    ForEach(PeripheralBatterySupport.sorted(peripherals)) { device in
                        HStack {
                            Image(systemName: "mouse.fill") // or switch based on device.kind
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(device.name)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text("\\(device.percent)%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(device.percent < 20 ? Color.red : .primary)
                        }
                    }
                }
            }""", mouse_ui)

with open('Sources/Vorssaint/UI/MenuPanel/BKBatteryHeroView.swift', 'w') as f:
    f.write(content)
