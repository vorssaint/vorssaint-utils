// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import zlib

/// A bounded, in-memory Open XML ZIP reader. Entries never become filesystem
/// paths. ZIP64, encryption, duplicate names and signed packages fail closed.
struct FinderPresentationArchive {
    struct Entry {
        let name: String
        let contents: Data
    }
    static let maximumArchiveBytes = 256 * 1024 * 1024
    static let maximumEntryBytes = 64 * 1024 * 1024
    static let maximumExpandedBytes = 512 * 1024 * 1024
    private let data: Data
    private let entries: [(name: String, offset: Int, packed: Int, size: Int, method: UInt16, crc: UInt32)]

    init(_ data: Data) throws {
        guard data.count >= 22, data.count <= Self.maximumArchiveBytes else { throw Self.invalid() }
        let end = stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1).first {
            data.u32($0) == 0x06054b50 && $0 + 22 + Int(data.u16($0 + 20)) == data.count
        }
        guard let end, data.u16(end + 4) == 0, data.u16(end + 6) == 0,
              data.u16(end + 8) == data.u16(end + 10) else { throw Self.invalid() }
        let count = Int(data.u16(end + 10))
        let directorySize = Int(data.u32(end + 12))
        var cursor = Int(data.u32(end + 16))
        let directoryStart = cursor
        guard (1...10_000).contains(count), cursor + directorySize == end else { throw Self.invalid() }
        var parsed: [(String, Int, Int, Int, UInt16, UInt32)] = []
        var names = Set<String>()
        var expanded = 0
        for _ in 0..<count {
            guard cursor + 46 <= end, data.u32(cursor) == 0x02014b50 else { throw Self.invalid() }
            let flags = data.u16(cursor + 8)
            let method = data.u16(cursor + 10)
            let packed = Int(data.u32(cursor + 20)), size = Int(data.u32(cursor + 24))
            let nameLength = Int(data.u16(cursor + 28))
            let extra = Int(data.u16(cursor + 30)), comment = Int(data.u16(cursor + 32))
            let local = Int(data.u32(cursor + 42))
            guard flags & 0x41 == 0, method == 0 || method == 8, data.u16(cursor + 34) == 0,
                  size <= Self.maximumEntryBytes, packed <= Self.maximumArchiveBytes,
                  cursor + 46 + nameLength + extra + comment <= end else { throw Self.invalid() }
            let nameBytes = data.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            guard let name = String(data: nameBytes, encoding: .utf8), !name.isEmpty,
                  !name.hasPrefix("/"), !name.contains("\\"),
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  !name.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }),
                  !name.lowercased().hasPrefix("_xmlsignatures/"), names.insert(name).inserted,
                  local + 30 <= directoryStart, data.u32(local) == 0x04034b50,
                  data.u16(local + 6) == flags, data.u16(local + 8) == method,
                  Int(data.u16(local + 26)) == nameLength else { throw Self.invalid() }
            let start = local + 30 + nameLength + Int(data.u16(local + 28))
            guard start <= directoryStart, packed <= directoryStart - start,
                  data.subdata(in: local + 30..<local + 30 + nameLength) == nameBytes else { throw Self.invalid() }
            expanded += size
            guard expanded <= Self.maximumExpandedBytes else { throw Self.invalid() }
            parsed.append((name, start, packed, size, method, data.u32(cursor + 16)))
            cursor += 46 + nameLength + extra + comment
        }
        guard cursor == end, names.contains("[Content_Types].xml"), names.contains("ppt/presentation.xml") else {
            throw Self.invalid()
        }
        self.data = data
        entries = parsed
    }

    /// Rewrites one entry at a time, preserving every part name and rejecting
    /// corrupt checksums before a transformed archive can be published.
    func rewrite(cancellation: FinderToolsCancellation, transform: (Entry) throws -> Data) throws -> Data {
        var output = Data(), directory = Data()
        for entry in entries {
            try cancellation.check()
            let packed = data.subdata(in: entry.offset..<entry.offset + entry.packed)
            let contents = entry.method == 0 ? packed : try Self.inflate(packed, size: entry.size)
            guard contents.count == entry.size, Self.checksum(contents) == entry.crc else { throw Self.invalid() }
            let revised = try transform(Entry(name: entry.name, contents: contents))
            guard revised.count <= Self.maximumEntryBytes else { throw Self.invalid() }
            let compressed = try Self.deflate(revised)
            let name = Data(entry.name.utf8), offset = UInt32(output.count), crc = Self.checksum(revised)
            output.appendLE(0x04034b50, bytes: 4)
            for value in [20, 0x800, 8, 0, 33] { output.appendLE(UInt32(value), bytes: 2) }
            for value in [crc, UInt32(compressed.count), UInt32(revised.count)] { output.appendLE(value, bytes: 4) }
            output.appendLE(UInt32(name.count), bytes: 2); output.appendLE(0, bytes: 2)
            output.append(name); output.append(compressed)
            directory.appendLE(0x02014b50, bytes: 4)
            for value in [20, 20, 0x800, 8, 0, 33] { directory.appendLE(UInt32(value), bytes: 2) }
            for value in [crc, UInt32(compressed.count), UInt32(revised.count)] { directory.appendLE(value, bytes: 4) }
            for value in [UInt32(name.count), 0, 0, 0, 0] { directory.appendLE(value, bytes: 2) }
            directory.appendLE(0, bytes: 4); directory.appendLE(offset, bytes: 4); directory.append(name)
            guard output.count + directory.count + 22 <= Self.maximumArchiveBytes else { throw Self.invalid() }
        }
        let directoryOffset = UInt32(output.count)
        output.append(directory)
        output.appendLE(0x06054b50, bytes: 4)
        for value in [0, 0, entries.count, entries.count] { output.appendLE(UInt32(value), bytes: 2) }
        output.appendLE(UInt32(directory.count), bytes: 4); output.appendLE(directoryOffset, bytes: 4)
        output.appendLE(0, bytes: 2)
        return output
    }

    private static func inflate(_ data: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw invalid()
        }
        defer { inflateEnd(&stream) }
        var result = Data(count: max(1, size))
        let status = data.withUnsafeBytes { source in
            result.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(max(1, size))
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, stream.total_out == size, stream.total_in == data.count else { throw invalid() }
        result.count = size
        return result
    }

    private static func deflate(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
                           ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw invalid() }
        defer { deflateEnd(&stream) }
        let capacity = Int(deflateBound(&stream, uLong(data.count)))
        var result = Data(count: capacity)
        let status = data.withUnsafeBytes { source in
            result.withUnsafeMutableBytes { destination in
                stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(capacity)
                return zlib.deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else { throw invalid() }
        result.count = Int(stream.total_out)
        return result
    }

    private static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(data.count))) }
    }

    private static func invalid() -> Error {
        FinderFileActionError.invalidRequest("Choose an unsigned, unencrypted PPTX under 256 MB with standard ZIP entries (up to 64 MB each and 512 MB expanded). The package may be unsupported or damaged.")
    }
}

private extension Data {
    func u16(_ at: Int) -> UInt16 { UInt16(self[at]) | UInt16(self[at + 1]) << 8 }
    func u32(_ at: Int) -> UInt32 { UInt32(u16(at)) | UInt32(u16(at + 2)) << 16 }
    mutating func appendLE(_ value: UInt32, bytes: Int) {
        for index in 0..<bytes { append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
}
