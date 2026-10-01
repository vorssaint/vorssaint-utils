// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The counters read so far and where reading stopped in each log, kept in
/// the app's own cache folder so a launch reads only what the agents wrote
/// since, instead of every log of the last thirteen weeks again. It holds
/// what the store holds in memory and nothing more: no prompt, reply or tool
/// output. Removed when the AI section is turned off.
///
/// A compact binary layout with shared strings: months of history hold
/// hundreds of thousands of responses that repeat a few models, folders and
/// sessions. A checksum covers everything after the magic, and every value
/// read back is checked the way the parser checks it. Anything unexpected,
/// including a file another build wrote, reads as nothing, and the logs are
/// read from their start as before.
enum AgentUsageArchive {
    struct Contents: Equatable {
        var providers: Set<AgentProvider>
        var store: AgentUsageStore.Saved
        var cursors: [AgentLogCursor.Saved]
    }

    private static let fileName = "agent-usage.bin"
    private static let magic: [UInt8] = Array("VAUA".utf8)
    private static let format = 1

    /// The parser and the store change between versions; what one build
    /// read is not taken for what another would have.
    static var build: String { build(info: Bundle.main.infoDictionary) }

    /// A Developer build keeps the version of the release it comes from, so
    /// its build stamp tells two of them apart.
    static func build(info: [String: Any]?) -> String {
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "")-\(info?["CFBundleVersion"] as? String ?? "")"
        guard let stamp = info?["VorssaintBuildCommit"] as? String else { return version }
        return "\(version) \(stamp)"
    }

    /// A cache the logs can rebuild: Time Machine leaves it out of backups,
    /// and if macOS clears it the next launch reads the logs from their start.
    private static var folder: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return caches.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("AgentUsage", isDirectory: true)
    }

    private static var url: URL? {
        folder?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> Contents? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data, build: build)
    }

    @discardableResult
    static func save(_ contents: Contents) -> Bool {
        guard let folder, let url, PrivateFileStore.createDirectory(at: folder, container: folder) else { return false }
        return PrivateFileStore.write(encode(contents, build: build), to: url)
    }

    /// The store and cursors a launch resumes with, given the logs `found`
    /// now, left as reading every log from its start would leave them. A log
    /// gone, replaced or rewritten since gives back what it gave, and one
    /// still there is read from its start again. A response it shared with
    /// another log kept the largest count either gave, so those logs are read
    /// again too. Limits and the plan describe the account when they were
    /// read, not the log, so the latest reading stays: a fresh read would
    /// fall back to an older one. `unchanged` tells whether the result is
    /// still what was saved.
    static func resume(_ contents: Contents, logs found: Set<String>, since horizon: Date)
        -> (store: AgentUsageStore, cursors: [String: AgentLogCursor], unchanged: Bool) {
        let store = AgentUsageStore(saved: contents.store)
        var cursors: [String: AgentLogCursor] = [:]
        for saved in contents.cursors where found.contains(saved.path) {
            cursors[saved.path] = AgentLogCursor(saved: saved)
        }
        var gone = store.files.subtracting(cursors.keys)
        let sharing = store.files(sharingWith: gone).subtracting(gone)
        for file in sharing { cursors[file] = nil }
        gone.formUnion(sharing)
        store.forget(files: gone)
        // Prices may be newer than the ones the counts were saved with.
        store.reprice()
        store.dropRecords(before: horizon)
        return (store, cursors, cursors.count == contents.cursors.count && store.saved == contents.store)
    }

    static func remove() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Layout

    static func encode(_ contents: Contents, build: String) -> Data {
        var body = Writer()
        body.string(build)
        body.count(contents.providers.count)
        for provider in contents.providers.sorted(by: { $0.rawValue < $1.rawValue }) { body.provider(provider) }
        let store = contents.store
        body.count(store.records.count)
        for entry in store.records {
            body.string(entry.key)
            body.record(entry.record)
            // The billed tokens are nearly always the recorded ones.
            let same = entry.billable.tokens == entry.record.tokens
            body.bool(same)
            if !same { body.tokens(entry.billable.tokens) }
            body.int(entry.billable.longCacheWrite)
            body.bool(entry.billable.fast)
            body.bool(entry.billable.domestic)
            body.int(entry.billable.webSearches)
            body.count(entry.sources.count)
            for source in entry.sources { body.string(source) }
        }
        body.count(store.limits.count)
        for limits in store.limits { body.limits(limits) }
        body.optional(store.codexPlan) { $0.string($1) }
        body.date(store.codexPlanObserved)
        for sessions in [store.turns, store.waiting] {
            body.count(sessions.count)
            for session in sessions { body.session(session) }
        }
        body.count(contents.cursors.count)
        for cursor in contents.cursors {
            body.string(cursor.path)
            body.provider(cursor.provider)
            body.unsigned(cursor.offset)
            body.unsigned(cursor.identity)
            body.bool(cursor.discarding)
            body.date(cursor.modified)
            body.state(cursor.state)
            body.unsigned(cursor.fingerprint)
        }
        var data = Data(magic)
        var header = Writer()
        header.int(format)
        header.count(body.strings.count)
        for string in body.strings {
            let bytes = Array(string.utf8)
            header.count(bytes.count)
            header.bytes.append(contentsOf: bytes)
        }
        data.append(contentsOf: header.bytes)
        data.append(contentsOf: body.bytes)
        let sum = checksum(header.bytes, body.bytes)
        withUnsafeBytes(of: sum.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    /// FNV-1a over the header and the body.
    private static func checksum(_ parts: [UInt8]...) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for part in parts {
            for byte in part { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3 }
        }
        return hash
    }

    static func decode(_ data: Data, build: String) -> Contents? {
        let sumSize = MemoryLayout<UInt64>.size
        guard data.count > magic.count + sumSize, data.prefix(magic.count).elementsEqual(magic) else { return nil }
        let payload = Array(data.dropFirst(magic.count).dropLast(sumSize))
        let sum = data.suffix(sumSize).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard checksum(payload) == sum else { return nil }
        var reader = Reader(bytes: payload)
        do {
            guard try reader.int() == format else { return nil }
            let strings = try reader.count()
            reader.strings.reserveCapacity(strings)
            for _ in 0..<strings {
                let length = try reader.count()
                reader.strings.append(String(decoding: try reader.take(length), as: UTF8.self))
            }
            guard try reader.string() == build else { return nil }
            var providers = Set<AgentProvider>()
            for _ in 0..<(try reader.count()) { providers.insert(try reader.provider()) }
            var store = AgentUsageStore.Saved()
            let records = try reader.count()
            store.records.reserveCapacity(records)
            for _ in 0..<records {
                let key = try reader.string()
                let record = try reader.record()
                let same = try reader.bool()
                let billable = AgentBillable(tokens: same ? record.tokens : try reader.tokens(),
                                             longCacheWrite: try reader.amount(), fast: try reader.bool(),
                                             domestic: try reader.bool(), webSearches: try reader.amount())
                var sources: [String] = []
                for _ in 0..<(try reader.count()) { sources.append(try reader.string()) }
                store.records.append(.init(key: key, record: record, billable: billable, sources: sources))
            }
            for _ in 0..<(try reader.count()) { store.limits.append(try reader.limits()) }
            store.codexPlan = try reader.optional { try $0.string() }
            store.codexPlanObserved = try reader.date()
            for _ in 0..<(try reader.count()) { store.turns.append(try reader.session()) }
            for _ in 0..<(try reader.count()) { store.waiting.append(try reader.session()) }
            var cursors: [AgentLogCursor.Saved] = []
            for _ in 0..<(try reader.count()) {
                cursors.append(AgentLogCursor.Saved(path: try reader.string(), provider: try reader.provider(),
                                                    offset: try reader.unsigned(), identity: try reader.unsigned(),
                                                    discarding: try reader.bool(), modified: try reader.date(),
                                                    state: try reader.state(), fingerprint: try reader.unsigned()))
            }
            guard reader.atEnd else { return nil }
            return Contents(providers: providers, store: store, cursors: cursors)
        } catch {
            return nil
        }
    }

    // MARK: Writing

    private struct Writer {
        var bytes: [UInt8] = []
        private(set) var strings: [String] = []
        private var positions: [String: Int] = [:]

        mutating func unsigned(_ value: UInt64) {
            var value = value
            while value >= 0x80 {
                bytes.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            bytes.append(UInt8(value))
        }

        mutating func int(_ value: Int) {
            unsigned(UInt64(bitPattern: Int64(value) << 1 ^ Int64(value) >> 63))
        }

        mutating func count(_ value: Int) { unsigned(UInt64(value)) }
        mutating func bool(_ value: Bool) { bytes.append(value ? 1 : 0) }

        mutating func double(_ value: Double) {
            withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
        }

        mutating func date(_ value: Date) { double(value.timeIntervalSinceReferenceDate) }

        mutating func string(_ value: String) {
            if let position = positions[value] {
                count(position)
            } else {
                positions[value] = strings.count
                count(strings.count)
                strings.append(value)
            }
        }

        mutating func optional<Value>(_ value: Value?, _ write: (inout Writer, Value) -> Void) {
            bool(value != nil)
            if let value { write(&self, value) }
        }

        mutating func provider(_ value: AgentProvider) { string(value.rawValue) }

        mutating func tokens(_ value: AgentTokens) {
            for part in [value.input, value.cacheWrite, value.cacheRead, value.output, value.reasoning] { int(part) }
        }

        mutating func record(_ value: AgentUsageRecord) {
            provider(value.provider)
            date(value.date)
            string(value.model)
            string(value.project)
            string(value.session)
            tokens(value.tokens)
            optional(value.cost) { $0.double($1) }
            double(value.savings)
        }

        mutating func limits(_ value: AgentLimits) {
            provider(value.provider)
            count(value.windows.count)
            for window in value.windows {
                string(window.id)
                string(window.kind.rawValue)
                optional(window.minutes) { $0.int($1) }
                optional(window.scope) { $0.string($1) }
                double(window.usedPercent)
                optional(window.resetsAt) { $0.date($1) }
            }
            date(value.observedAt)
            switch value.source {
            case .sessionLog: count(0)
            case .claudeApp: count(1)
            case .account: count(2)
            }
        }

        mutating func session(_ value: AgentLiveSession) {
            string(value.id)
            provider(value.provider)
            date(value.started)
            date(value.lastActivity)
            string(value.model)
            string(value.project)
            tokens(value.tokens)
            double(value.cost)
        }

        mutating func state(_ value: AgentLogState) {
            string(value.session)
            string(value.project)
            string(value.model)
            bool(value.turnOpen)
            bool(value.sawUsageRecords)
            optional(value.lastTotal) { $0.tokens($1) }
            bool(value.fast)
        }
    }

    // MARK: Reading

    private struct Malformed: Error {}

    private struct Reader {
        let bytes: [UInt8]
        var position = 0
        var strings: [String] = []

        init(bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { position == bytes.count }

        mutating func byte() throws -> UInt8 {
            guard position < bytes.count else { throw Malformed() }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func take(_ length: Int) throws -> ArraySlice<UInt8> {
            guard length <= bytes.count - position else { throw Malformed() }
            defer { position += length }
            return bytes[position..<position + length]
        }

        mutating func unsigned() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let next = try byte()
                guard shift < 64 else { throw Malformed() }
                value |= UInt64(next & 0x7F) << shift
                if next < 0x80 { return value }
                shift += 7
            }
        }

        mutating func int() throws -> Int {
            let raw = try unsigned()
            return Int(Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1))
        }

        /// A count can never exceed the bytes left, which keeps a damaged
        /// file from asking for an enormous allocation.
        mutating func count() throws -> Int {
            let value = try unsigned()
            guard value <= UInt64(bytes.count - position) else { throw Malformed() }
            return Int(value)
        }

        mutating func bool() throws -> Bool {
            switch try byte() {
            case 0: return false
            case 1: return true
            default: throw Malformed()
            }
        }

        mutating func double() throws -> Double {
            var raw: UInt64 = 0
            for (shift, byte) in try take(8).enumerated() { raw |= UInt64(byte) << (8 * UInt64(shift)) }
            let value = Double(bitPattern: raw)
            guard value.isFinite else { throw Malformed() }
            return value
        }

        mutating func date() throws -> Date { Date(timeIntervalSinceReferenceDate: try double()) }

        mutating func string() throws -> String {
            let position = try unsigned()
            guard position < UInt64(strings.count) else { throw Malformed() }
            return strings[Int(position)]
        }

        mutating func optional<Value>(_ read: (inout Reader) throws -> Value) throws -> Value? {
            try bool() ? try read(&self) : nil
        }

        mutating func provider() throws -> AgentProvider {
            guard let provider = AgentProvider(rawValue: try string()) else { throw Malformed() }
            return provider
        }

        /// Counts are never negative in a log, and never more than the rest
        /// of the file here.
        mutating func tokens() throws -> AgentTokens {
            AgentTokens(input: try amount(), cacheWrite: try amount(), cacheRead: try amount(),
                        output: try amount(), reasoning: try amount())
        }

        mutating func amount() throws -> Int {
            let value = try int()
            guard value >= 0 else { throw Malformed() }
            return value
        }

        mutating func record() throws -> AgentUsageRecord {
            AgentUsageRecord(provider: try provider(), date: try date(), model: try string(), project: try string(),
                             session: try string(), tokens: try tokens(), cost: try optional { try $0.double() },
                             savings: try double())
        }

        mutating func limits() throws -> AgentLimits {
            let provider = try provider()
            var windows: [AgentLimitWindow] = []
            for _ in 0..<(try count()) {
                let id = try string()
                guard let kind = AgentLimitWindow.Kind(rawValue: try string()) else { throw Malformed() }
                windows.append(AgentLimitWindow(id: id, kind: kind, minutes: try optional { try $0.int() },
                                                scope: try optional { try $0.string() }, usedPercent: try double(),
                                                resetsAt: try optional { try $0.date() }))
            }
            let observed = try date()
            let source: AgentLimits.Source
            switch try unsigned() {
            case 0: source = .sessionLog
            case 1: source = .claudeApp
            case 2: source = .account
            default: throw Malformed()
            }
            return AgentLimits(provider: provider, windows: windows, observedAt: observed, source: source)
        }

        mutating func session() throws -> AgentLiveSession {
            AgentLiveSession(id: try string(), provider: try provider(), started: try date(),
                             lastActivity: try date(), model: try string(), project: try string(),
                             tokens: try tokens(), cost: try double())
        }

        mutating func state() throws -> AgentLogState {
            AgentLogState(session: try string(), project: try string(), model: try string(), turnOpen: try bool(),
                          sawUsageRecords: try bool(), lastTotal: try optional { try $0.tokens() }, fast: try bool())
        }
    }
}
