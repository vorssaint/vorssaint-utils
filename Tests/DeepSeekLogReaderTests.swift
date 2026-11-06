import Foundation

enum DeepSeekLogReaderTests {
    private static let first = Data(base64Encoded: "KLUv/SAMYQAAeyJmaXJzdCI6MX0K")!
    private static let second = Data(base64Encoded: "KLUv/SAZyQAAeyJzZWNvbmQiOjJ9CnsidGhpcmQiOjN9Cg==")!
    private static let replacement = Data(base64Encoded: "KLUv/SASkQAAeyJyZXBsYWNlbWVudCI6NH0K")!

    static func run(_ suite: TestSuite) {
        guard AgentDeepSeekLogReader.supportsCompression else {
            print("SKIP DeepSeekLogReaderTests: libzstd is unavailable")
            suite.expect(true, "DeepSeek compressed-reader tests explicitly skip without libzstd")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try incremental(suite, directory: directory)
            try interrupted(suite, directory: directory)
            try rewritten(suite, directory: directory)
            try invalid(suite, directory: directory)
        } catch {
            suite.expect(false, "DeepSeek compressed-reader fixture failed: \(error)")
        }
    }

    private static func read(_ cursor: AgentLogCursor, shouldContinue: () -> Bool = { true }) -> [String] {
        var lines: [String] = []
        AgentDeepSeekLogReader.readAppended(cursor, shouldContinue: shouldContinue) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        return lines
    }

    private static func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private static func incremental(_ suite: TestSuite, directory: URL) throws {
        let url = directory.appendingPathComponent("incremental.zstd")
        try first.write(to: url)
        let cursor = AgentLogCursor(path: url.path, provider: .deepseek)
        suite.expect(read(cursor) == ["{\"first\":1}"], "DeepSeek reads the first independent Zstandard frame")
        suite.expect(cursor.offset == UInt64(first.count), "DeepSeek cursor tracks compressed byte boundaries")
        let saved = cursor.saved
        try append(second, to: url)
        suite.expect(read(cursor) == ["{\"second\":2}", "{\"third\":3}"],
                     "DeepSeek delivers every line from the appended frame without replaying history")
        suite.expect(read(cursor).isEmpty, "DeepSeek unchanged compressed logs do not repeat events")
        guard let restored = AgentLogCursor(saved: saved) else {
            suite.expect(false, "DeepSeek compressed cursor restores after an append")
            return
        }
        suite.expect(read(restored) == ["{\"second\":2}", "{\"third\":3}"],
                     "DeepSeek saved offsets resume at compressed frame boundaries")
    }

    private static func interrupted(_ suite: TestSuite, directory: URL) throws {
        let url = directory.appendingPathComponent("interrupted.zstd")
        let cut = second.count / 2
        try (first + second.prefix(cut)).write(to: url)
        let cursor = AgentLogCursor(path: url.path, provider: .deepseek)
        suite.expect(read(cursor) == ["{\"first\":1}"] && cursor.offset == UInt64(first.count),
                     "DeepSeek leaves a torn final frame unconsumed")
        let saved = cursor.saved
        try append(second.dropFirst(cut), to: url)
        suite.expect(read(cursor) == ["{\"second\":2}", "{\"third\":3}"],
                     "DeepSeek finishes a partial frame when its remaining bytes arrive")
        suite.expect(AgentLogCursor(saved: saved) != nil,
                     "DeepSeek partial frames do not corrupt the saved compressed fingerprint")
        let cancelled = AgentLogCursor(path: url.path, provider: .deepseek)
        suite.expect(read(cancelled, shouldContinue: { false }).isEmpty && cancelled.offset == 0,
                     "DeepSeek respects cancellation before reading a compressed frame")
    }

    private static func rewritten(_ suite: TestSuite, directory: URL) throws {
        let url = directory.appendingPathComponent("rewritten.zstd")
        try (first + second).write(to: url)
        let cursor = AgentLogCursor(path: url.path, provider: .deepseek)
        _ = read(cursor)
        try first.write(to: url)
        suite.expect(read(cursor) == ["{\"first\":1}"] && cursor.restarted,
                     "DeepSeek restarts a truncated compressed log")
        try replacement.write(to: url, options: .atomic)
        suite.expect(read(cursor) == ["{\"replacement\":4}"],
                     "DeepSeek restarts a replaced compressed file")
        let saved = cursor.saved
        try (first + second).write(to: url)
        suite.expect(AgentLogCursor(saved: saved) == nil,
                     "DeepSeek refuses saved progress after an in-place rewrite")
        suite.expect(read(cursor) == ["{\"first\":1}", "{\"second\":2}", "{\"third\":3}"],
                     "DeepSeek detects a growing in-place rewrite using its fingerprint")
    }

    private static func invalid(_ suite: TestSuite, directory: URL) throws {
        let url = directory.appendingPathComponent("invalid.zstd")
        try Data("not a Zstandard frame".utf8).write(to: url)
        let cursor = AgentLogCursor(path: url.path, provider: .deepseek)
        suite.expect(read(cursor).isEmpty && cursor.offset == 0,
                     "DeepSeek rejects invalid compressed data without advancing its cursor")
        let folder = AgentLogCursor(path: directory.path, provider: .deepseek)
        suite.expect(read(folder).isEmpty && folder.offset == 0,
                     "DeepSeek compressed reader ignores non-regular paths")
    }
}
