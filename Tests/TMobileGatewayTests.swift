// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TMobileGatewayTests {
    static func run(_ suite: TestSuite) {
        addresses(suite)
        parsing(suite)
        radioDetails(suite)
        explicitNodeMetadata(suite)
        diagnostics(suite)
        suite.expect((0...5).map { TMobileGatewaySupport.pollingDelay(errorStreak: $0) }
                     == [15, 30, 60, 120, 120, 120], "gateway polling backs off with a 120-second limit")
        MainActor.assumeIsolated { transport(suite) }
    }

    private static func explicitNodeMetadata(_ suite: TestSuite) {
        let fixture = #"{"signal":{"4g":{"eNodeBID":123,"ecgi":"001-01-12345","supportedBands":["B2","b66","b66","n41"]},"5g":{"cid":21,"gNBID":456,"eNBID":789,"ecgi":"0x310260ABCDEF","supportedBands":["n25","n41","b2"]}}}"#
        let parsed = try? TMobileGatewaySupport.parse(Data(fixture.utf8))
        suite.expect(parsed?.lte?.eNodeBID == 123 && parsed?.lte?.gNodeBID == nil
                     && parsed?.fiveG?.gNodeBID == 456 && parsed?.fiveG?.eNodeBID == nil,
                     "reported LTE and NR node identities stay technology-specific")
        suite.expect(parsed?.lte?.ecgi == "001-01-12345" && parsed?.fiveG?.ecgi == "0x310260ABCDEF",
                     "opaque global-cell identity text retains leading zeroes and reported format")
        suite.expect(parsed?.lte?.supportedBands == ["b2", "b66"] && parsed?.fiveG?.supportedBands == ["n25", "n41"]
                     && parsed?.lte?.bands.isEmpty == true && parsed?.fiveG?.bands.isEmpty == true,
                     "supported inventory is validated independently without inventing active bands")
        suite.expect(TMobileGatewayConnectedRadioSupport.select(from: parsed) == nil,
                     "node metadata and capability inventory do not create a connected menu indicator")
        for bad in ["0", "--", "1::2", "x123", "1.5", "private text", String(repeating: "1", count: 65)] {
            let data = try! JSONSerialization.data(withJSONObject: ["signal": ["4g": ["bands": ["b2"], "ecgi": bad, "eNBID": 268435456]]])
            let rejected = try? TMobileGatewaySupport.parse(data)
            suite.expect(rejected?.lte?.ecgi == nil && rejected?.lte?.eNodeBID == nil,
                         "malformed global identities and overflowing LTE node IDs remain unavailable")
        }
    }

    private static func radioDetails(_ suite: TestSuite) {
        let fixture = #"{"signal":{"4g":{"bars":2,"bands":[" B66 ","b66","n41","b0","b999","b2"],"cid":268435455,"antennaUsed":"internal","bandwidth":"20 MHz","earfcn":"1234","pci":503,"tac":65535,"cqi":15,"gNBID":123},"5g":{"bars":3,"bands":["N41","n71"],"cid":"68719476735","antennaUsed":"External","bandwidth":100,"nrarfcn":520000,"pci":1007,"tac":16777215,"cqi":30,"sector":{"gNBID":"4294967295"}},"generic":{"apn":"fast.t-mobile.com"}},"sim":{"imsi":"private-id"},"gps":{"latitude":1,"longitude":2}}"#
        let parsed = try? TMobileGatewaySupport.parse(Data(fixture.utf8))
        suite.expect(parsed?.lte?.bands == ["b66", "b2"] && parsed?.fiveG?.bands == ["n41", "n71"],
                     "band normalization deduplicates and rejects a wrong radio prefix or malformed band")
        suite.expect(parsed?.lte?.cellID == 268_435_455 && parsed?.fiveG?.cellID == 68_719_476_735,
                     "LTE 28-bit and NR 36-bit cell IDs retain exact integer precision")
        suite.expect(parsed?.lte?.antenna == "Internal" && parsed?.fiveG?.antenna == "External"
                     && parsed?.apn == "fast.t-mobile.com", "only known antenna values and the public APN are retained")
        suite.expect(parsed?.lte?.bandwidthMHz == 20 && parsed?.fiveG?.bandwidthMHz == 100
                     && parsed?.lte?.channel == 1234 && parsed?.fiveG?.channel == 520_000,
                     "optional channel and bandwidth fields decode only when supplied")
        suite.expect(parsed?.lte?.physicalCellID == 503 && parsed?.fiveG?.physicalCellID == 1007
                     && parsed?.lte?.trackingAreaCode == 65_535 && parsed?.fiveG?.trackingAreaCode == 16_777_215,
                     "PCI and TAC limits distinguish LTE from NR")
        suite.expect(parsed?.lte?.gNodeBID == nil && parsed?.fiveG?.gNodeBID == UInt32.max
                     && parsed?.lte?.cqi == 15 && parsed?.fiveG?.cqi == 30,
                     "gNB IDs are explicit 5G fields rather than an LTE cell calculation")
        let malformed = #"{"signal":{"4g":{"bands":["b2"],"cid":268435456,"pci":504,"tac":65536,"earfcn":262144,"cqi":31,"bandwidth":401,"antennaUsed":"unknown","rsrp":0,"rsrq":5,"rssi":99,"sinr":99},"5g":{"bands":["n41"],"cid":"68719476736","pci":1008,"tac":16777216,"nrarfcn":3279166,"cqi":-1,"bandwidth":0,"gNBID":"4294967296"}}}"#
        let rejected = try? TMobileGatewaySupport.parse(Data(malformed.utf8))
        for radio in [rejected?.lte, rejected?.fiveG] {
            suite.expect(radio?.cellID == nil && radio?.physicalCellID == nil && radio?.trackingAreaCode == nil
                         && radio?.channel == nil && radio?.cqi == nil && radio?.gNodeBID == nil
                         && radio?.bandwidthMHz == nil, "out-of-range radio identifiers and channel fields stay unavailable")
        }
        suite.expect(rejected?.lte?.antenna == nil && rejected?.lte?.rsrp == nil && rejected?.lte?.rsrq == nil
                     && rejected?.lte?.rssi == nil && rejected?.lte?.sinr == nil,
                     "unknown antenna modes and impossible measurement sentinels are not displayed as real readings")
        for value in ["true", "false", "-1", "1.5", #""1.5""#, #""1e3""#, #""NaN""#,
                      #""18446744073709551616""#] {
            let data = Data("{\"signal\":{\"5g\":{\"bands\":[\"n41\"],\"cid\":\(value),\"pci\":\(value)}}}".utf8)
            let snapshot = try? TMobileGatewaySupport.parse(data)
            suite.expect(snapshot?.fiveG?.cellID == nil && snapshot?.fiveG?.physicalCellID == nil,
                         "cell identifiers reject booleans, fractions, signs, exponent strings and overflow: \(value)")
        }
        let only5GID = try? TMobileGatewaySupport.parse(Data(#"{"signal":{"5g":{"cid":12345}}}"#.utf8))
        suite.expect(only5GID?.fiveG?.cellID == 12345 && only5GID?.fiveG?.gNodeBID == nil,
                     "a 5G cell ID is retained without inventing a gNB ID")
    }

    private static func diagnostics(_ suite: TestSuite) {
        suite.expect(TMobileGatewayDiagnostics.quality(for: nil, metric: .rsrp) == .unknown
                     && TMobileGatewayDiagnostics.quality(for: .nan, metric: .sinr) == .unknown
                     && TMobileGatewayDiagnostics.quality(for: 0, metric: .rsrp) == .unknown,
                     "quality guidance does not turn missing or impossible readings into a grade")
        suite.expect([-106.0, -105, -95, -85].map { TMobileGatewayDiagnostics.quality(for: $0, metric: .rsrp) }
                     == [.poor, .fair, .good, .excellent], "RSRP guidance has explicit boundary behavior")
        suite.expect([-16.0, -15, -10, -7].map { TMobileGatewayDiagnostics.quality(for: $0, metric: .rsrq) }
                     == [.poor, .fair, .good, .excellent], "RSRQ guidance has explicit boundary behavior")
        suite.expect([-1.0, 0, 13, 20].map { TMobileGatewayDiagnostics.quality(for: $0, metric: .sinr) }
                     == [.poor, .fair, .good, .excellent], "SINR guidance distinguishes interference-dominated readings")
        suite.expect(TMobileGatewayDiagnostics.quality(for: -55, metric: .rssi) == .unknown,
                     "RSSI alone does not manufacture a bandwidth-independent quality grade")
        suite.expect(TMobileGatewayDiagnostics.lteENodeBID(cellID: 12_345 * 256 + 7) == 12_345
                     && TMobileGatewayDiagnostics.lteSectorID(cellID: 12_345 * 256 + 7) == 7,
                     "conventional LTE macro estimate preserves the separate eight-bit local cell")
        suite.expect(TMobileGatewayDiagnostics.lteENodeBID(cellID: 68_719_476_735) == nil
                     && TMobileGatewayDiagnostics.lteSectorID(cellID: 268_435_456) == nil,
                     "LTE estimate rejects IDs outside the LTE range instead of truncating NR data")
        suite.expect(TMobileGatewayDiagnostics.bandDescription("N41", strings: TMobileGatewayStrings.localized(.enUS))?.contains("2.5 GHz") == true
                     && TMobileGatewayDiagnostics.bandDescription("n71", strings: TMobileGatewayStrings.localized(.enUS))?.contains("600 MHz") == true
                     && TMobileGatewayDiagnostics.bandDescription("n99", strings: TMobileGatewayStrings.localized(.enUS)) == nil,
                     "known bands have sourced context while unknown bands get no guessed frequency")
        let weak = TMobileGatewaySnapshot(model: nil, firmware: nil, uptime: nil, registration: nil, roaming: false,
                                         lte: TMobileRadioSignal(bars: 5, bands: ["b66"], rsrp: -118,
                                                                rsrq: -18, rssi: -60, sinr: -2), fiveG: nil)
        let tips = TMobileGatewayDiagnostics.tips(for: weak, strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(tips.contains { $0.contains("higher shelf") }
                     && tips.contains { $0.contains("Interference") }
                     && tips.contains { $0.contains("does not prove a 5G outage") },
                     "tips explain weak power, interference and missing 5G without using bars as speed")
        let fiveG = TMobileGatewaySnapshot(model: nil, firmware: nil, uptime: nil, registration: nil, roaming: false,
                                          lte: weak.lte, fiveG: TMobileRadioSignal(bars: 1, bands: ["n41"],
                                                                                 rsrp: -80, rsrq: -6, rssi: -55, sinr: 25))
        let fiveGTips = TMobileGatewayDiagnostics.tips(for: fiveG, strings: TMobileGatewayStrings.localized(.enUS))
        suite.expect(!fiveGTips.contains { $0.contains("higher shelf") }
                     && fiveGTips.contains { $0.contains("band name does not predict") },
                     "tips use available 5G measurements and avoid promising band-based performance")
    }

    private static func addresses(_ suite: TestSuite) {
        for address in ["http://192.168.12.1", "http://192.168.12.1/", "https://10.0.0.1",
                        "http://172.16.0.1:8080", "https://172.31.255.254:443"] {
            suite.expect(TMobileGatewaySupport.privateLANBaseURL(address) != nil,
                         "canonical RFC1918 gateway address is accepted: \(address)")
        }
        for address in ["http://192.168.12.1/TMI", "http://192.168.12.1//", "http://192.168.12.1?x=1",
                        "http://192.168.12.1#fragment", "http://user:pass@192.168.12.1", "http://192.168.12.1@8.8.8.8",
                        "http://8.8.8.8", "http://127.0.0.1", "http://169.254.1.1", "http://100.64.0.1",
                        "http://172.15.0.1", "http://172.32.0.1", "http://192.169.0.1", "http://router.local",
                        "http://[::1]", "http://[::ffff:192.168.12.1]", "http://3232238593", "http://192.168.12",
                        "http://192.168.012.1", "http://0xc0.0xa8.0xc.1", "http://192%2e168.12.1",
                        "http://192.168.12.256", "http://192.168.12.1:", "http://192.168.12.1:0",
                        "http://192.168.12.1:080", "http://192.168.12.1:65536", "http://192.168.12.1\\@8.8.8.8",
                        " http://192.168.12.1", "http://192.168.12.1 ", "HTTP://192.168.12.1", "ftp://192.168.12.1"] {
            suite.expect(TMobileGatewaySupport.privateLANBaseURL(address) == nil,
                         "unsafe or noncanonical gateway address is rejected: \(address)")
        }
    }

    private static func parsing(_ suite: TestSuite) {
        let fixture = #"{"device":{"model":"TMO-G4AR","softwareVersion":"1.00.18","serialNumber":"omitted"},"time":{"upTime":"86400"},"signal":{"4g":{"bars":4.0,"bands":["b2"],"rsrp":-92,"rsrq":"-10","rssi":-64,"sinr":"9"},"5g":{"bars":"3","bands":["n41"],"rsrp":"-97","rsrq":-11,"rssi":-68,"sinr":6},"generic":{"registration":"registered","roaming":false}},"sim":{"imsi":"omitted"},"gps":{"latitude":1},"clients":[{"name":"omitted"}]}"#
        let snapshot = try? TMobileGatewaySupport.parse(Data(fixture.utf8))
        suite.expect(snapshot?.model == "TMO-G4AR" && snapshot?.firmware == "1.00.18"
                     && snapshot?.uptime == 86400, "gateway device and numeric-string uptime decode")
        suite.expect(snapshot?.lte?.bars == 4 && snapshot?.lte?.rsrq == -10 && snapshot?.lte?.sinr == 9,
                     "LTE signal accepts numbers and numeric strings")
        suite.expect(snapshot?.fiveG?.bands == ["n41"] && snapshot?.fiveG?.rsrp == -97
                     && snapshot?.primaryRadioLabel == "5G", "5G RSRP selects the primary radio")
        suite.expect(snapshot?.registration == "registered" && snapshot?.roaming == false,
                     "connection state keeps a real false value")
        suite.expect(!String(reflecting: snapshot).contains("omitted"),
                     "private serial, SIM and client data in a response do not survive normalization")

        let nullFixture = #"{"device":{"friendlyName":"5G Gateway","model":null,"softwareVersion":null},"time":{"upTime":-1},"signal":{"4g":{"rsrp":"-104","bands":"b66"},"5g":{"rsrp":null,"bars":null},"generic":{"roaming":"false"}}}"#
        let missing = try? TMobileGatewaySupport.parse(Data(nullFixture.utf8))
        suite.expect(missing?.model == "5G Gateway" && missing?.firmware == nil && missing?.uptime == nil,
                     "missing values stay unavailable and friendlyName is a model fallback")
        suite.expect(missing?.fiveG == nil && missing?.lte?.bands == ["b66"] && missing?.primaryRadioLabel == "LTE",
                     "a null 5G signal falls back to LTE without manufacturing zero readings")
        suite.expect(missing?.roaming == false, "string booleans decode")

        let malformedMetrics = #"{"signal":{"5g":{"bars":true,"bands":[null,12,"n71"],"rsrp":"nan","rsrq":"infinity","rssi":false,"sinr":null},"generic":{"roaming":"unknown"}},"time":{"upTime":true}}"#
        let malformed = try? TMobileGatewaySupport.parse(Data(malformedMetrics.utf8))
        suite.expect(malformed?.fiveG?.bars == nil && malformed?.fiveG?.rsrp == nil
                     && malformed?.fiveG?.rsrq == nil && malformed?.fiveG?.rssi == nil,
                     "booleans, nonfinite strings and nulls cannot become signal numbers")
        suite.expect(malformed?.fiveG?.bands == ["n71"] && malformed?.roaming == nil && malformed?.uptime == nil,
                     "malformed values are omitted while valid fields survive")
        let empty = try? TMobileGatewaySupport.parse(Data(#"{"signal":{"4g":null,"5g":{}}}"#.utf8))
        suite.expect(empty != nil && empty?.lte == nil && empty?.fiveG == nil && empty?.primaryRadioLabel == nil,
                     "absent radio measurements remain absent")
        for invalid in ["not JSON", "[]", "null", "{}", #"{"error":"blocked"}"#, #"{"signal":[]}"#] {
            do {
                _ = try TMobileGatewaySupport.parse(Data(invalid.utf8))
                suite.expect(false, "malformed gateway response is rejected")
            } catch {
                suite.expect(error as? TMobileGatewayFailure == .invalidResponse,
                             "malformed gateway response produces the typed failure")
            }
        }
    }

    @MainActor private static func transport(_ suite: TestSuite) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TMobileGatewayTestProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "must-be-removed", "Cookie": "must-be-removed"]
        let service = TMobileGatewayService(configuration: configuration)
        suite.expect(configuration.urlCache == nil && configuration.httpCookieStorage == nil
                     && configuration.urlCredentialStorage == nil && !configuration.httpShouldSetCookies,
                     "gateway transport disables cache, cookies and credential storage")
        suite.expect(configuration.connectionProxyDictionary?.isEmpty == true
                     && configuration.timeoutIntervalForRequest == 15 && configuration.timeoutIntervalForResource == 15,
                     "gateway transport bypasses proxies and has bounded timeouts")

        TMobileGatewayTestProtocol.reset(status: 200, body: #"{"signal":{"5g":{"rsrp":-97}}}"#)
        service.start(baseURL: "http://192.168.12.1")
        wait { service.phase == .ready }
        suite.expect(service.phase == .ready && service.snapshot?.fiveG?.rsrp == -97,
                     "credential-free gateway GET publishes a decoded snapshot")
        let requests = TMobileGatewayTestProtocol.requests
        suite.expect(requests.count == 1 && requests.first?.httpMethod == "GET"
                     && requests.first?.url?.path == "/TMI/v1/gateway" && requests.first?.url?.query == "get=all",
                     "gateway service uses only the public status endpoint")
        suite.expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil
                     && requests.first?.value(forHTTPHeaderField: "Cookie") == nil && requests.first?.httpBody == nil,
                     "gateway requests send no credentials or body")
        service.cancel()
        suite.expect(service.phase == .idle && service.snapshot == nil, "cancelling clears gateway state")

        for (status, body, failure) in [(401, "{}", TMobileGatewayFailure.authenticationRequired),
                                       (403, "{}", .authenticationRequired), (500, "{}", .unavailable),
                                       (302, "{}", .unavailable), (200, "not JSON", .invalidResponse)] {
            TMobileGatewayTestProtocol.reset(status: status, body: body)
            service.start(baseURL: "http://192.168.12.1")
            wait { if case .failed = service.phase { return true }; return false }
            suite.expect(service.phase == .failed(failure) && service.snapshot == nil,
                         "HTTP \(status) and invalid bodies produce the right failure without stale metrics")
            suite.expect(TMobileGatewayTestProtocol.requests.count == 1,
                         "gateway failure never starts login or follows another endpoint")
            service.cancel()
        }
        TMobileGatewayTestProtocol.reset(status: 200, body: "{}")
        service.start(baseURL: "http://8.8.8.8")
        suite.expect(service.phase == .failed(.invalidAddress) && TMobileGatewayTestProtocol.requests.isEmpty,
                     "invalid gateway addresses never start a request")

        TMobileGatewayTestProtocol.reset(status: 200, body: #"{"signal":{"5g":{"rsrp":-90}}}"#, hold: true)
        service.start(baseURL: "http://192.168.12.1")
        wait { TMobileGatewayTestProtocol.requests.count == 1 }
        service.refresh()
        wait { TMobileGatewayTestProtocol.requests.count == 2 }
        suite.expect(TMobileGatewayTestProtocol.requests.count == 2 && TMobileGatewayTestProtocol.maximumActive == 1,
                     "refresh immediately replaces an in-flight request after cancellation without overlap")
        service.cancel()
        wait { TMobileGatewayTestProtocol.active == 0 }
        suite.expect(TMobileGatewayTestProtocol.active == 0 && service.phase == .idle && service.snapshot == nil,
                     "cancel retires an in-flight gateway request and prevents later publication")

        let delegate = TMobileGatewaySessionDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "http://192.168.12.1/TMI/v1/gateway?get=all")!
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "https://example.invalid/"])!
        var refused = false
        delegate.urlSession(session, task: session.dataTask(with: original), willPerformHTTPRedirection: response,
                            newRequest: URLRequest(url: URL(string: "https://example.invalid/")!)) { refused = $0 == nil }
        suite.expect(refused, "redirect delegate rejects every destination before a second request")
    }

    private static func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
    }
}

/// Intercepts every request, including any unexpected URL, so tests cannot reach a router.
private final class TMobileGatewayTestProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var captured: [URLRequest] = []
    private static var status = 200
    private static var body = Data()
    private static var hold = false
    private static var inFlight = 0
    private static var peak = 0
    private var counted = false

    static var requests: [URLRequest] { lock.withLock { captured } }
    static var active: Int { lock.withLock { inFlight } }
    static var maximumActive: Int { lock.withLock { peak } }

    static func reset(status: Int, body: String, hold: Bool = false) {
        lock.withLock {
            captured = []; self.status = status; self.body = Data(body.utf8); self.hold = hold
            inFlight = 0; peak = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.lock.withLock { () -> (Int, Data, Bool) in
            Self.captured.append(request)
            Self.inFlight += 1; Self.peak = max(Self.peak, Self.inFlight); counted = true
            return (Self.status, Self.body, Self.hold)
        }
        guard !reply.2 else { return }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        finishCount()
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { finishCount() }

    private func finishCount() {
        Self.lock.withLock {
            if counted { Self.inFlight -= 1; counted = false }
        }
    }
}
