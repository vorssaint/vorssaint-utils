// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

let connect = HotspotSnapshot.Action(name: "AXCustomAction:Connect", description: "Connect")
let disconnect = HotspotSnapshot.Action(name: "AXCustomAction:Disconnect", description: "Disconnect")
func snapshot(_ nodes: [HotspotSnapshot.Node], ssid: String? = nil) -> HotspotSnapshot {
    HotspotSnapshot(generation: UUID(), nodes: nodes, ssid: ssid)
}
func node(_ parent: Int?, _ id: String = "", _ text: String = "", _ actions: [HotspotSnapshot.Action] = []) -> HotspotSnapshot.Node {
    .init(parent: parent, identifier: id, text: text, actions: actions)
}
let device = "Alice’s iPhone"
let found = snapshot([node(nil), node(0, "wifi-network-\(device)-hotspot"), node(0, "", device, [connect])])
precondition(found.hotspotNames == [device])
precondition(found.connectAction(for: device)?.index == 2)
precondition(found.connectAction(for: "Other phone") == nil)
let unrelated = snapshot([node(nil), node(0, "wifi-network-\(device)-hotspot"), node(3, "", device, [connect])])
precondition(unrelated.connectAction(for: device) == nil)
let already = snapshot([node(nil), node(0, "wifi-network-\(device)-hotspot"), node(0, "", device, [disconnect])])
precondition(already.connectAction(for: device) == nil)
let joining = snapshot([node(nil, "wifi-current-network-hotspot"), node(nil, "wifi-current-network-name", device + " Connecting…")])
precondition(!joining.isConnected(to: device))
let done = snapshot([node(nil, "wifi-current-network-hotspot"), node(nil, "wifi-current-network-name", device + " Connected")])
precondition(done.isConnected(to: device))
precondition(!done.isConnected(to: "Alice"))
let ordinary = snapshot([node(nil, "wifi-current-network-name", device + " Connected")], ssid: device)
precondition(!ordinary.isConnected(to: device))
let localized = snapshot([node(nil), node(0, "wifi-network-\(device)-hotspot"), node(0, "", device, [.init(name: "AXCustomAction:連線", description: "連線")])])
precondition(localized.connectAction(for: device)?.index == 2)
let joiningWithSSID = snapshot(joining.nodes, ssid: device)
precondition(!joiningWithSSID.isConnected(to: device))
let plainCurrent = snapshot([node(nil, "wifi-current-network-hotspot"), node(nil, "wifi-current-network-name", device)], ssid: device)
precondition(plainCurrent.isConnected(to: device))
precondition(done.hotspotNames == [device])
precondition(joining.hotspotNames.isEmpty)
let staleSSID = snapshot(done.nodes, ssid: "Other hotspot")
precondition(!staleSSID.isConnected(to: device))
precondition(staleSSID.hotspotNames.isEmpty)
// One fixture per supported app locale; these are Apple's current Wi-Fi strings.
let locales: [(String, String, String)] = [
    ("en-US", "Connect", "Connected"), ("pt-BR", "Conectar", "Conectado"),
    ("tr", "Bağlan", "Bağlandı"), ("ru", "Подключиться", "Подключено"),
    ("es", "Conectar", "Con conexión"), ("sk", "Pripojiť", "Pripojené"),
    ("de", "Verbinden", "Verbunden"), ("fr", "Connecter", "Connecté"),
    ("it", "Connetti", "Connessione attiva"), ("ja", "接続", "接続済み"),
    ("ko", "연결", "연결됨"), ("uk", "Підʼєднатись", "Підʼєднано"),
    ("zh-Hans", "连接", "已连接"), ("zh-TW", "連線", "已連線"),
    ("zh-HK", "連線", "已連線")
]
for (locale, action, status) in locales {
    let available = snapshot([node(nil), node(0, "wifi-network-\(device)-hotspot"), node(0, "", device, [.init(name: "AXCustomAction:" + action, description: action)])])
    precondition(available.connectAction(for: device) != nil, locale)
    let current = snapshot([node(nil, "wifi-current-network-hotspot"), node(nil, "wifi-current-network-name", device + " " + status)])
    precondition(current.isConnected(to: device), locale)
    precondition(current.hotspotNames == [device], locale)
}
for redacted: String? in [nil, "", "<redacted>"] {
    let multiline = snapshot([node(nil, "wifi-current-network-hotspot"), node(nil, "wifi-current-network-name", device + "\nConnected")], ssid: redacted)
    precondition(multiline.isConnected(to: device))
    precondition(multiline.hotspotNames == [device])
}
precondition(HotspotActionResult.shouldPoll(.success))
precondition(HotspotActionResult.shouldPoll(.cannotComplete))
for failure: AXError in [.failure, .illegalArgument, .invalidUIElement, .actionUnsupported, .apiDisabled, .notImplemented] {
    precondition(!HotspotActionResult.shouldPoll(failure))
}
// An uncertain action response never replaces completed-state evidence.
precondition(HotspotActionResult.shouldPoll(.cannotComplete) && !joining.isConnected(to: device))
print("PASS: exact hotspot selection, unrelated network rejection, completed-state discovery, stale SSID rejection, all 15 locales, and AX timeout polling classification")

let splitStatus = snapshot([node(nil, "wifi-current-network-hotspot"), node(0, "wifi-current-network-name", device), node(0, "wifi-current-network-status", "Connected")])
precondition(splitStatus.isConnected(to: device))
let splitJoining = snapshot([node(nil, "wifi-current-network-hotspot"), node(0, "wifi-current-network-name", device), node(0, "wifi-current-network-status", "Connecting…")])
precondition(!splitJoining.isConnected(to: device))
