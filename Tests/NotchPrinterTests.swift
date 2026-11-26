// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchPrinterTests {
    static func run(_ suite: TestSuite) {
        reportContracts(suite)
        readingContracts(suite)
        packetContracts(suite)
        requestContracts(suite)
        gateContracts(suite)
        cloudContracts(suite)
    }

    private static func reportContracts(_ suite: TestSuite) {
        var status = PrinterStatus()
        status.merge(["gcode_state": "RUNNING", "mc_percent": 42, "mc_remaining_time": 65,
                      "layer_num": 10, "total_layer_num": 120, "nozzle_temper": 219.6,
                      "nozzle_target_temper": 220, "bed_temper": 64.9, "bed_target_temper": 65,
                      "subtask_name": "Benchy.gcode.3mf"])
        suite.expect(status.state == .printing && status.percent == 42 && status.remainingMinutes == 65
                     && status.layer == 10 && status.totalLayers == 120 && status.jobName == "Benchy",
                     "a full report fills every field and drops the slicer's extensions from the name")

        status.merge(["mc_percent": 43, "layer_num": 11])
        suite.expect(status.state == .printing && status.percent == 43 && status.layer == 11
                     && status.nozzle == 219.6 && status.jobName == "Benchy",
                     "a partial report from an A1 keeps every field it does not carry")

        status.merge(["mc_percent": "44", "nozzle_temper": "221.0", "gcode_state": "pause"])
        suite.expect(status.percent == 44 && status.nozzle == 221 && status.state == .paused,
                     "numbers sent as text and a lowercase state are read the same way")

        status.merge(["mc_percent": 140, "mc_remaining_time": -3])
        suite.expect(status.percent == 100 && status.remainingMinutes == 0,
                     "progress and time left stay within sensible bounds")

        suite.expect(PrinterJobState(report: "SLICING") == .unknown
                     && [PrinterJobState.preparing, .printing, .paused].allSatisfy(\.isActive)
                     && ![PrinterJobState.idle, .finished, .failed, .unknown].contains { $0.isActive },
                     "only a job on the printer counts as a live activity")

        let payload = Data(#"{"print":{"command":"push_status","gcode_state":"FINISH"}}"#.utf8)
        suite.expect(NotchPrinterSupport.printReport(payload)?["gcode_state"] as? String == "FINISH"
                     && NotchPrinterSupport.printReport(Data(#"{"info":{}}"#.utf8)) == nil
                     && NotchPrinterSupport.printReport(Data("not json".utf8)) == nil,
                     "only the print part of a report is read, and anything else is ignored")
    }

    private static func readingContracts(_ suite: TestSuite) {
        var status = PrinterStatus()
        status.state = .printing
        status.percent = 7
        suite.expect(NotchPrinterSupport.stripReading(status) == "7%", "a running job shows its progress")
        status.state = .preparing
        status.nozzle = 180.4
        suite.expect(NotchPrinterSupport.stripReading(status) == "180°", "a job warming up shows the nozzle heating")
        status.state = .idle
        suite.expect(NotchPrinterSupport.stripReading(status).isEmpty, "an idle printer shows nothing")
        suite.expect(NotchPrinterSupport.temperaturePair(64.6, 65) == "65° / 65°"
                     && NotchPrinterSupport.temperaturePair(24, 0) == "24°"
                     && NotchPrinterSupport.temperaturePair(nil, nil) == "–",
                     "a heater shows its target only while it has one")
        suite.expect(NotchPrinterSupport.jobName("  .gcode.3mf ") == nil
                     && NotchPrinterSupport.jobName("Part.GCODE") == "Part",
                     "an empty name stays empty and extensions are matched in any case")
        suite.expect(AppLanguage.allCases.allSatisfy { language in
            let text = FeatureStrings.notchPrinter(language)
            return text.layer(3, of: 9).contains("3") && text.layer(3, of: 9).contains("9")
                && text.left("5m").contains("5m") && !text.title.isEmpty && !text.summary.isEmpty
        }, "every language names the page and fills its layer and time left")
    }

    private static func packetContracts(_ suite: TestSuite) {
        suite.expect(BambuMQTTClient.remainingLength(0) == Data([0x00])
                     && BambuMQTTClient.remainingLength(127) == Data([0x7F])
                     && BambuMQTTClient.remainingLength(128) == Data([0x80, 0x01])
                     && BambuMQTTClient.remainingLength(16_383) == Data([0xFF, 0x7F])
                     && BambuMQTTClient.remainingLength(16_384) == Data([0x80, 0x80, 0x01]),
                     "remaining length uses MQTT's variable-length encoding")

        let topic = "device/01P00A000000000/report"
        let payload = Data(String(repeating: "x", count: 300).utf8)
        var body = Data([UInt8(topic.utf8.count >> 8), UInt8(topic.utf8.count & 0xFF)])
        body.append(Data(topic.utf8))
        body.append(payload)
        let packet = BambuMQTTClient.packet(type: 0x30, body: body)
        let partial = packet.prefix(packet.count - 1)
        suite.expect(BambuMQTTClient.nextPacket(in: partial) == nil,
                     "a packet still arriving waits for its last byte")
        var stream = packet
        stream.append(Data([0xD0, 0x00]))
        if let (header, read, used) = BambuMQTTClient.nextPacket(in: stream),
           let (name, data, id) = BambuMQTTClient.parsePublish(header: header, body: read) {
            suite.expect(header == 0x30 && used == packet.count && name == topic && data == payload && id == nil,
                         "a QoS 0 publish yields its topic and payload and leaves the next packet in place")
            let rest = stream.subdata(in: (stream.startIndex + used)..<stream.endIndex)
            suite.expect(BambuMQTTClient.nextPacket(in: rest).map { $0.0 == 0xD0 && $0.1.isEmpty } == true,
                         "the packet after it is read on its own")
        } else {
            suite.expect(false, "a whole publish is parsed")
        }

        var qos = Data([0x00, 0x01, 0x74, 0x12, 0x34])
        qos.append(Data("{}".utf8))
        let parsed = BambuMQTTClient.parsePublish(header: 0x32, body: qos)
        suite.expect(parsed?.0 == "t" && parsed?.1 == Data("{}".utf8) && parsed?.2 == 0x1234,
                     "a QoS 1 publish carries the packet id it must be acknowledged with")
        suite.expect(BambuMQTTClient.parsePublish(header: 0x30, body: Data([0x00, 0x09, 0x61])) == nil,
                     "a topic longer than its packet is rejected")
        suite.expect(BambuMQTTClient.refusal(5).contains("refused"),
                     "a refused sign-in says so")
    }

    private static func requestContracts(_ suite: TestSuite) {
        let request = NotchPrinterSupport.pushAllRequest(sequence: 7)
        let object = (try? JSONSerialization.jsonObject(with: request)) as? [String: [String: String]]
        suite.expect(object?["pushing"]?["command"] == "pushall" && object?["pushing"]?["sequence_id"] == "7",
                     "the first request asks the printer for a full report")
        suite.expect(NotchPrinterSupport.reportTopic(serial: "ABC") == "device/ABC/report"
                     && NotchPrinterSupport.requestTopic(serial: "ABC") == "device/ABC/request",
                     "reports and requests use the printer's own topics")
    }

    private static func gateContracts(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.notch-printer"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        defer { defaults.removePersistentDomain(forName: domain) }
        // Registration is process-wide, so the suite stays unregistered:
        // an unset switch reads as off, as the registered default has it.
        suite.expect(!AppFeature.notchPrinter.isAvailable(in: defaults)
                     && !NotchPrinterSupport.isEnabled(in: defaults)
                     && !NotchSupport.modules(in: defaults).contains(.printer),
                     "the printer ships uninstalled and its page stays off")
        defaults.set(true, forKey: AppFeature.notchPrinter.availabilityKey)
        suite.expect(!NotchSupport.modules(in: defaults).contains(.printer),
                     "installing it alone does not add the page")
        defaults.set(true, forKey: DefaultsKey.notchPrinterEnabled)
        suite.expect(NotchSupport.modules(in: defaults).contains(.printer),
                     "turning it on adds the page")
        suite.expect(NotchCompactActivity.printer.module == .printer
                     && NotchEvent.printer.preferenceKey == DefaultsKey.notchPrinterEnabled,
                     "its activity opens its page and its notices follow its switch")
    }

    private static func cloudContracts(_ suite: TestSuite) {
        suite.expect((try? BambuCloudAPI.loginResult(["accessToken": "abc", "loginType": ""])) == .token("abc"),
                     "a password that is enough on its own signs in at once")
        suite.expect((try? BambuCloudAPI.loginResult(["accessToken": "", "loginType": "verifyCode"])) == .needsEmailCode,
                     "an account that needs the emailed code asks for it")
        suite.expect((try? BambuCloudAPI.loginResult(["accessToken": "", "loginType": "tfa", "tfaKey": "k1"]))
                        == .needsTwoFactor(key: "k1"),
                     "an account with an authenticator asks for its code and keeps the key")
        var rejected = ""
        do { _ = try BambuCloudAPI.loginResult(["error": "Incorrect password"]) } catch {
            rejected = error.localizedDescription
        }
        suite.expect(rejected == "Incorrect password", "Bambu's own reason for a refusal is shown")

        let devices = BambuCloudAPI.parseDevices(["devices": [
            ["dev_id": "03900D5C1506288", "name": "A1 ของฉัน", "online": true, "dev_product_name": "A1"],
            ["dev_id": "", "name": "broken"],
            ["dev_id": "01P00A0000", "name": "", "online": false],
        ]])
        suite.expect(devices.map(\.serial) == ["03900D5C1506288", "01P00A0000"]
                     && devices[0].name == "A1 ของฉัน" && devices[0].model == "A1" && devices[0].online
                     && devices[1].name == "01P00A0000" && !devices[1].online,
                     "printers without a serial are skipped and an unnamed one goes by its serial")
        suite.expect(BambuCloudAPI.parseDevices([:]).isEmpty, "an account without printers lists none")
        suite.expect(BambuCloudAPI.mqttHost == "us.mqtt.bambulab.com", "the global broker is used")
    }
}
