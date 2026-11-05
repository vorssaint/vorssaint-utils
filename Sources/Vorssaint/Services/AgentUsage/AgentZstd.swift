// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A Zstandard decoder (RFC 8878) for the session logs Codex compresses once
/// a session is over. macOS ships no Zstandard library, and the logs need
/// only part of the format: frames without a dictionary, decoded in order.
/// The output is handed over in pieces, so a log of hundreds of megabytes
/// holds only its window in memory. The content checksum is not verified: a
/// damaged frame fails on its own structure, and a log that reads oddly
/// gives no usage.
enum AgentZstd {
    enum Failure: Error, Equatable {
        case corrupt
        case truncated
        /// A dictionary, or a window larger than a log needs.
        case unsupported
    }

    /// The largest window decoded. Codex compresses with a few megabytes;
    /// anything this large is not one of its logs.
    static let maximumWindow = 1 << 27
    static let blockMaximum = 1 << 17

    /// Decodes every frame of `input` and hands the output to `output` in
    /// pieces of about `piece` bytes. False when `shouldContinue` stopped it
    /// before the end.
    @discardableResult
    static func decode(_ input: UnsafeRawBufferPointer, piece: Int = 4 << 20,
                       shouldContinue: () -> Bool = { true },
                       output: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        guard let base = input.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return true }
        return try decode(Source(memory: base, count: input.count), piece: piece,
                          shouldContinue: shouldContinue, output: output)
    }

    /// Decodes the file at `path`, read a little at a time rather than
    /// mapped: a file cut short while mapped would bring the app down.
    @discardableResult
    static func decode(file path: String, piece: Int = 4 << 20, shouldContinue: () -> Bool = { true },
                       output: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        // Without O_NONBLOCK a FIFO named like a log would block the open.
        let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw Failure.truncated }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw Failure.unsupported }
        return try decode(Source(descriptor: descriptor), piece: piece, shouldContinue: shouldContinue, output: output)
    }

    private static func decode(_ source: Source, piece: Int, shouldContinue: () -> Bool,
                               output: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        while source.ensure(1) {
            guard source.ensure(4) else { throw Failure.truncated }
            let magic = read32(source.base + source.position)
            // Skippable frames carry data for other tools.
            if magic & 0xFFFF_FFF0 == 0x184D_2A50 {
                guard source.ensure(8) else { throw Failure.truncated }
                var size = Int(read32(source.base + source.position + 4))
                source.position += 8
                while size > 0 {
                    guard source.ensure(1) else { throw Failure.truncated }
                    let skipped = min(size, source.remaining)
                    source.position += skipped
                    size -= skipped
                }
                continue
            }
            guard magic == 0xFD2F_B528 else { throw Failure.corrupt }
            source.position += 4
            let frame = try Frame(source, piece: piece)
            guard try frame.decode(shouldContinue: shouldContinue, output: output) else { return false }
        }
        return true
    }

    /// The whole output of `data`, for tests and small inputs.
    static func decompress(_ data: Data) throws -> Data {
        var result = Data()
        try data.withUnsafeBytes { raw in
            _ = try decode(raw) { result.append(contentsOf: $0) }
        }
        return result
    }

    fileprivate static func read32(_ pointer: UnsafePointer<UInt8>) -> UInt32 {
        UInt32(littleEndian: UnsafeRawPointer(pointer).loadUnaligned(as: UInt32.self))
    }

    /// The index of the highest bit set; `value` is above zero.
    fileprivate static func highestBit(_ value: Int) -> Int {
        Int.bitWidth - 1 - value.leadingZeroBitCount
    }
}

// MARK: Input

/// The compressed bytes: all in memory, or read from a file as decoding
/// goes, so only a block or two of input is held at once. A pointer into
/// it stays good until the next `ensure`, which may move what is unread.
private final class Source {
    private(set) var base: UnsafePointer<UInt8>
    var position = 0
    private(set) var end: Int
    private let storage: UnsafeMutablePointer<UInt8>?
    private let capacity: Int
    private let descriptor: Int32
    private var exhausted: Bool

    var remaining: Int { end - position }

    init(memory: UnsafePointer<UInt8>, count: Int) {
        base = memory
        end = count
        storage = nil
        capacity = count
        descriptor = -1
        exhausted = true
    }

    /// Room for the largest block with its header, many times over.
    init(descriptor: Int32, capacity: Int = 1 << 20) {
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        self.storage = storage
        base = UnsafePointer(storage)
        end = 0
        self.capacity = capacity
        self.descriptor = descriptor
        exhausted = false
    }

    deinit { storage?.deallocate() }

    /// Makes `count` bytes from `position` on readable, reading more when a
    /// file holds them. False when the input ends first.
    func ensure(_ count: Int) -> Bool {
        if end - position >= count { return true }
        guard !exhausted, let storage, count <= capacity else { return false }
        let left = end - position
        if position > 0 {
            memmove(storage, storage + position, left)
            position = 0
            end = left
        }
        while end - position < count {
            let read = Darwin.read(descriptor, storage + end, capacity - end)
            if read > 0 {
                end += read
            } else if read < 0, errno == EINTR {
                continue
            } else {
                exhausted = true
                break
            }
        }
        return end - position >= count
    }
}

// MARK: Bit streams

/// Reads a stream written backward, as Huffman and FSE streams are: the
/// last byte's highest set bit marks where the stream starts. `position`
/// counts the bits still unread; it goes below zero once a decoder reads
/// past the start, where every bit reads as zero.
private struct BackwardBits {
    let base: UnsafePointer<UInt8>
    let count: Int
    var position: Int

    init(_ base: UnsafePointer<UInt8>, count: Int) throws {
        guard count > 0, base[count - 1] != 0 else { throw AgentZstd.Failure.corrupt }
        self.base = base
        self.count = count
        position = (count - 1) * 8 + AgentZstd.highestBit(Int(base[count - 1]))
    }

    /// The next `width` bits, up to 57, without reading them.
    func peek(_ width: Int) -> Int {
        let start = position - width
        if start >= 0 {
            let byte = start >> 3
            let word: UInt64
            if byte + 8 <= count {
                word = UInt64(littleEndian: UnsafeRawPointer(base + byte).loadUnaligned(as: UInt64.self))
            } else {
                word = tail(from: byte)
            }
            return Int(truncatingIfNeeded: (word >> UInt64(start & 7)) & ((1 << UInt64(width)) - 1))
        }
        let available = position
        guard available > 0 else { return 0 }
        let word = count >= 8
            ? UInt64(littleEndian: UnsafeRawPointer(base).loadUnaligned(as: UInt64.self)) : tail(from: 0)
        return Int(truncatingIfNeeded: (word & ((1 << UInt64(available)) - 1)) << UInt64(-start))
    }

    mutating func read(_ width: Int) -> Int {
        guard width > 0 else { return 0 }
        let value = peek(width)
        position -= width
        return value
    }

    private func tail(from byte: Int) -> UInt64 {
        var word: UInt64 = 0
        var index = count - 1
        while index >= byte {
            word = word << 8 | UInt64(base[index])
            index -= 1
        }
        return word
    }
}

/// Reads a table description, written forward from its first byte. Bits
/// past the end read as zero; the caller checks how far reading went.
private struct ForwardBits {
    let base: UnsafePointer<UInt8>
    let count: Int
    var position = 0

    init(_ base: UnsafePointer<UInt8>, count: Int) {
        self.base = base
        self.count = count
    }

    mutating func read(_ width: Int) -> Int {
        var value = 0
        for bit in 0..<width {
            let at = position + bit
            let byte = at >> 3
            if byte < count, (base[byte] >> UInt8(at & 7)) & 1 == 1 { value |= 1 << bit }
        }
        position += width
        return value
    }
}

// MARK: Tables

/// A finite state entropy decoding table: each state gives a symbol, the
/// number of bits to read, and the base the bits are added to for the next
/// state.
private struct FSETable {
    struct Entry {
        var symbol: UInt8 = 0
        var bits: UInt8 = 0
        var base: UInt16 = 0
    }

    let log: Int
    let entries: [Entry]

    /// A table that always gives `symbol` and reads nothing.
    init(single symbol: UInt8) {
        log = 0
        entries = [Entry(symbol: symbol, bits: 0, base: 0)]
    }

    /// Builds the table from normalized counts, -1 standing for "less than one".
    init(counts: [Int], log: Int) throws {
        let size = 1 << log
        var symbols = [UInt8](repeating: 0, count: size)
        var next = [Int](repeating: 0, count: counts.count)
        var high = size - 1
        for (symbol, count) in counts.enumerated() where count == -1 {
            symbols[high] = UInt8(symbol)
            high -= 1
            next[symbol] = 1
        }
        let step = (size >> 1) + (size >> 3) + 3
        let mask = size - 1
        var position = 0
        for (symbol, count) in counts.enumerated() where count > 0 {
            next[symbol] = count
            for _ in 0..<count {
                symbols[position] = UInt8(symbol)
                repeat { position = (position + step) & mask } while position > high
            }
        }
        // Spreading visits every cell once only when the counts add up.
        guard position == 0 else { throw AgentZstd.Failure.corrupt }
        var entries = [Entry](repeating: Entry(), count: size)
        for index in 0..<size {
            let symbol = Int(symbols[index])
            let state = next[symbol]
            next[symbol] += 1
            let bits = log - AgentZstd.highestBit(state)
            entries[index] = Entry(symbol: symbols[index], bits: UInt8(bits), base: UInt16((state << bits) - size))
        }
        self.log = log
        self.entries = entries
    }

    /// Reads a table description and returns the table and the bytes it took.
    static func read(_ source: UnsafePointer<UInt8>, count: Int, maxLog: Int,
                     maxSymbol: Int) throws -> (table: FSETable, used: Int) {
        var bits = ForwardBits(source, count: count)
        let log = bits.read(4) + 5
        guard log <= maxLog else { throw AgentZstd.Failure.corrupt }
        var remaining = 1 << log
        var counts: [Int] = []
        while remaining > 0 {
            guard counts.count <= maxSymbol else { throw AgentZstd.Failure.corrupt }
            let width = AgentZstd.highestBit(remaining + 1) + 1
            var value = bits.read(width)
            let lowerMask = (1 << (width - 1)) - 1
            let threshold = (1 << width) - 1 - (remaining + 1)
            if value & lowerMask < threshold {
                bits.position -= 1
                value &= lowerMask
            } else if value > lowerMask {
                value -= threshold
            }
            let probability = value - 1
            remaining -= abs(probability)
            guard remaining >= 0 else { throw AgentZstd.Failure.corrupt }
            counts.append(probability)
            if probability == 0 {
                var repeats = bits.read(2)
                while true {
                    for _ in 0..<repeats {
                        guard counts.count <= maxSymbol else { throw AgentZstd.Failure.corrupt }
                        counts.append(0)
                    }
                    guard repeats == 3 else { break }
                    repeats = bits.read(2)
                }
            }
        }
        let used = (bits.position + 7) >> 3
        guard used <= count else { throw AgentZstd.Failure.truncated }
        return (try FSETable(counts: counts, log: log), used)
    }

    // The distributions a block can name instead of describing its own.
    static let literalLengths = try! FSETable(counts: [
        4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1,
        -1, -1, -1, -1,
    ], log: 6)
    static let matchLengths = try! FSETable(counts: [
        1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1,
    ], log: 6)
    static let offsets = try! FSETable(counts: [
        1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
    ], log: 5)
}

/// A Huffman decoding table indexed by the next `maxBits` bits: each entry
/// holds the symbol in its low byte and the code's length above it.
private struct HuffmanTable {
    let maxBits: Int
    let entries: [UInt16]

    /// Reads a tree description and returns the table and the bytes it took.
    static func read(_ source: UnsafePointer<UInt8>, count: Int) throws -> (table: HuffmanTable, used: Int) {
        guard count >= 1 else { throw AgentZstd.Failure.truncated }
        let header = Int(source[0])
        var weights: [Int]
        let used: Int
        if header < 128 {
            // Weights compressed with FSE, two states taking turns.
            guard header > 0, count - 1 >= header else { throw AgentZstd.Failure.truncated }
            let description = try FSETable.read(source + 1, count: header, maxLog: 6, maxSymbol: 12)
            guard description.used < header else { throw AgentZstd.Failure.corrupt }
            let table = description.table
            var bits = try BackwardBits(source + 1 + description.used, count: header - description.used)
            var first = bits.read(table.log)
            var second = bits.read(table.log)
            weights = []
            weights.reserveCapacity(256)
            func next(_ state: inout Int) -> Int {
                let entry = table.entries[state]
                state = Int(entry.base) + bits.read(Int(entry.bits))
                return Int(entry.symbol)
            }
            while true {
                guard weights.count <= 253 else { throw AgentZstd.Failure.corrupt }
                weights.append(next(&first))
                if bits.position < 0 {
                    weights.append(Int(table.entries[second].symbol))
                    break
                }
                weights.append(next(&second))
                if bits.position < 0 {
                    weights.append(Int(table.entries[first].symbol))
                    break
                }
            }
            used = 1 + header
        } else {
            // Four bits a weight, the first in the high half of each byte.
            let symbols = header - 127
            let bytes = (symbols + 1) / 2
            guard count - 1 >= bytes else { throw AgentZstd.Failure.truncated }
            weights = (0..<symbols).map { index in
                let byte = Int(source[1 + index / 2])
                return index % 2 == 0 ? byte >> 4 : byte & 0xF
            }
            used = 1 + bytes
        }
        return (try HuffmanTable(weights: weights), used)
    }

    /// The last symbol's weight is left out: it is what makes the total a
    /// power of two.
    init(weights given: [Int]) throws {
        var weights = given
        var total = 0
        for weight in weights where weight > 0 {
            guard weight <= 11 else { throw AgentZstd.Failure.corrupt }
            total += 1 << (weight - 1)
        }
        guard total > 0 else { throw AgentZstd.Failure.corrupt }
        let maxBits = AgentZstd.highestBit(total) + 1
        let left = (1 << maxBits) - total
        guard maxBits <= 11, left & (left - 1) == 0, weights.count < 256 else { throw AgentZstd.Failure.corrupt }
        weights.append(AgentZstd.highestBit(left) + 1)
        var entries = [UInt16](repeating: 0, count: 1 << maxBits)
        var position = 0
        // Longest codes first, each weight's symbols in order.
        for weight in 1...maxBits {
            let span = 1 << (weight - 1)
            let entry = UInt16(maxBits + 1 - weight) << 8
            for (symbol, value) in weights.enumerated() where value == weight {
                guard position + span <= entries.count else { throw AgentZstd.Failure.corrupt }
                for index in position..<(position + span) { entries[index] = entry | UInt16(symbol) }
                position += span
            }
        }
        guard position == entries.count else { throw AgentZstd.Failure.corrupt }
        self.maxBits = maxBits
        self.entries = entries
    }
}

// MARK: Frames

/// One frame's decoding: its window of recent output, and the tables and
/// offsets a block can carry over to the next.
private final class Frame {
    private let source: Source
    private let hasChecksum: Bool
    private let window: Int
    private let piece: Int
    private let capacity: Int
    private let buffer: UnsafeMutablePointer<UInt8>
    private let literals: UnsafeMutablePointer<UInt8>
    /// Bytes in the buffer, and how many of them were handed over.
    private var written = 0
    private var emitted = 0
    private var huffman: HuffmanTable?
    private var literalLengths: FSETable?
    private var offsets: FSETable?
    private var matchLengths: FSETable?
    private var repeats = (1, 4, 8)

    // The baselines and extra bits of each length code.
    private static let literalBase: [Int] = Array(0...15) + [
        16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536,
    ]
    private static let literalBits: [Int] = Array(repeating: 0, count: 16) + [
        1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    ]
    private static let matchBase: [Int] = Array(3...34) + [
        35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051, 4099, 8195, 16387, 32771, 65539,
    ]
    private static let matchBits: [Int] = Array(repeating: 0, count: 32) + [
        1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    ]

    init(_ source: Source, piece: Int) throws {
        self.source = source
        self.piece = max(piece, 1)
        // The longest header: its descriptor, window, dictionary and size.
        _ = source.ensure(14)
        let input = source.base
        let end = source.end
        var position = source.position
        guard position < end else { throw AgentZstd.Failure.truncated }
        let descriptor = Int(input[position])
        position += 1
        guard descriptor & 0x08 == 0 else { throw AgentZstd.Failure.corrupt }
        let singleSegment = descriptor & 0x20 != 0
        hasChecksum = descriptor & 0x04 != 0
        var window = 0
        if !singleSegment {
            guard position < end else { throw AgentZstd.Failure.truncated }
            let byte = Int(input[position])
            position += 1
            let windowLog = 10 + (byte >> 3)
            guard windowLog <= 30 else { throw AgentZstd.Failure.unsupported }
            let base = 1 << windowLog
            window = base + (base >> 3) * (byte & 7)
        }
        let dictionaryBytes = [0, 1, 2, 4][descriptor & 3]
        guard end - position >= dictionaryBytes else { throw AgentZstd.Failure.truncated }
        var dictionary = 0
        for index in 0..<dictionaryBytes { dictionary |= Int(input[position + index]) << (8 * index) }
        position += dictionaryBytes
        guard dictionary == 0 else { throw AgentZstd.Failure.unsupported }
        let flag = descriptor >> 6
        let sizeBytes = flag == 0 ? (singleSegment ? 1 : 0) : [0, 2, 4, 8][flag]
        guard end - position >= sizeBytes else { throw AgentZstd.Failure.truncated }
        var contentSize: Int?
        if sizeBytes > 0 {
            var value: UInt64 = 0
            for index in 0..<sizeBytes { value |= UInt64(input[position + index]) << UInt64(8 * index) }
            if sizeBytes == 2 { value += 256 }
            guard value <= UInt64(Int.max) else { throw AgentZstd.Failure.unsupported }
            contentSize = Int(value)
        }
        position += sizeBytes
        if singleSegment { window = contentSize ?? 0 }
        guard window <= AgentZstd.maximumWindow else { throw AgentZstd.Failure.unsupported }
        self.window = window
        source.position = position
        // The window, a piece's worth before it is handed over, and room
        // for one more block; less when the frame says it is smaller.
        var room = window + self.piece
        if let contentSize { room = min(room, contentSize) }
        capacity = room + AgentZstd.blockMaximum
        buffer = .allocate(capacity: capacity)
        literals = .allocate(capacity: AgentZstd.blockMaximum)
    }

    deinit {
        buffer.deallocate()
        literals.deallocate()
    }

    func decode(shouldContinue: () -> Bool, output: (UnsafeRawBufferPointer) throws -> Void) throws -> Bool {
        while true {
            guard source.ensure(3) else { throw AgentZstd.Failure.truncated }
            let at = source.base + source.position
            let header = Int(at[0]) | Int(at[1]) << 8 | Int(at[2]) << 16
            source.position += 3
            let type = (header >> 1) & 3
            let size = header >> 3
            guard size <= AgentZstd.blockMaximum, type != 3 else { throw AgentZstd.Failure.corrupt }
            // A block of repeats holds the one byte it repeats.
            guard source.ensure(type == 1 ? 1 : size) else { throw AgentZstd.Failure.truncated }
            try makeRoom(output)
            let block = source.base + source.position
            switch type {
            case 0:
                memcpy(buffer + written, block, size)
                written += size
                source.position += size
            case 1:
                memset(buffer + written, Int32(block[0]), size)
                written += size
                source.position += 1
            default:
                try decompressBlock(block, count: size)
                source.position += size
            }
            if written - emitted >= piece { try emit(output) }
            if header & 1 == 1 { break }
            guard shouldContinue() else { return false }
        }
        if hasChecksum {
            guard source.ensure(4) else { throw AgentZstd.Failure.truncated }
            source.position += 4
        }
        try emit(output)
        return true
    }

    private func emit(_ output: (UnsafeRawBufferPointer) throws -> Void) throws {
        guard written > emitted else { return }
        try output(UnsafeRawBufferPointer(start: buffer + emitted, count: written - emitted))
        emitted = written
    }

    /// Hands over what is waiting and keeps only the window, once another
    /// block might not fit.
    private func makeRoom(_ output: (UnsafeRawBufferPointer) throws -> Void) throws {
        guard written + AgentZstd.blockMaximum > capacity else { return }
        try emit(output)
        // A frame claiming less content than its window leaves less room;
        // a match reaching past what is kept then fails as corrupt.
        let keep = min(window, written, capacity - AgentZstd.blockMaximum)
        memmove(buffer, buffer + (written - keep), keep)
        written = keep
        emitted = keep
    }

    // MARK: Blocks

    private func decompressBlock(_ source: UnsafePointer<UInt8>, count: Int) throws {
        let (literalCount, used) = try decodeLiterals(source, count: count)
        try decodeSequences(source + used, count: count - used, literalCount: literalCount)
    }

    /// Fills `literals` and returns how many there are and the bytes read.
    private func decodeLiterals(_ source: UnsafePointer<UInt8>, count: Int) throws -> (Int, Int) {
        guard count >= 1 else { throw AgentZstd.Failure.truncated }
        let first = Int(source[0])
        let format = (first >> 2) & 3
        func byte(_ index: Int) throws -> Int {
            guard index < count else { throw AgentZstd.Failure.truncated }
            return Int(source[index])
        }
        switch first & 3 {
        case 0, 1:
            let regenerated: Int
            let header: Int
            switch format {
            case 0, 2:
                regenerated = first >> 3
                header = 1
            case 1:
                regenerated = (first >> 4) + (try byte(1) << 4)
                header = 2
            default:
                regenerated = (first >> 4) + (try byte(1) << 4) + (try byte(2) << 12)
                header = 3
            }
            guard regenerated <= AgentZstd.blockMaximum else { throw AgentZstd.Failure.corrupt }
            if first & 3 == 0 {
                guard count - header >= regenerated else { throw AgentZstd.Failure.truncated }
                memcpy(literals, source + header, regenerated)
                return (regenerated, header + regenerated)
            }
            memset(literals, Int32(try byte(header)), regenerated)
            return (regenerated, header + 1)
        default:
            var streams = 4
            let regenerated: Int
            let compressed: Int
            let header: Int
            switch format {
            case 0, 1:
                let value = first | (try byte(1)) << 8 | (try byte(2)) << 16
                regenerated = (value >> 4) & 0x3FF
                compressed = (value >> 14) & 0x3FF
                header = 3
                if format == 0 { streams = 1 }
            case 2:
                let value = first | (try byte(1)) << 8 | (try byte(2)) << 16 | (try byte(3)) << 24
                regenerated = (value >> 4) & 0x3FFF
                compressed = (value >> 18) & 0x3FFF
                header = 4
            default:
                let value = first | (try byte(1)) << 8 | (try byte(2)) << 16 | (try byte(3)) << 24 | (try byte(4)) << 32
                regenerated = (value >> 4) & 0x3FFFF
                compressed = (value >> 22) & 0x3FFFF
                header = 5
            }
            guard regenerated <= AgentZstd.blockMaximum else { throw AgentZstd.Failure.corrupt }
            guard count - header >= compressed else { throw AgentZstd.Failure.truncated }
            var data = source + header
            var left = compressed
            if first & 3 == 2 {
                let tree = try HuffmanTable.read(data, count: left)
                huffman = tree.table
                data += tree.used
                left -= tree.used
            }
            guard let table = huffman else { throw AgentZstd.Failure.corrupt }
            if streams == 1 {
                try decodeStream(table, data, count: left, into: literals, length: regenerated)
            } else {
                guard left >= 6 else { throw AgentZstd.Failure.truncated }
                let sizes = [Int(data[0]) | Int(data[1]) << 8, Int(data[2]) | Int(data[3]) << 8,
                             Int(data[4]) | Int(data[5]) << 8]
                let total = left - 6
                guard sizes[0] + sizes[1] + sizes[2] <= total else { throw AgentZstd.Failure.corrupt }
                let segment = (regenerated + 3) / 4
                guard 3 * segment <= regenerated else { throw AgentZstd.Failure.corrupt }
                var stream = data + 6
                for index in 0..<4 {
                    let size = index < 3 ? sizes[index] : total - sizes[0] - sizes[1] - sizes[2]
                    let length = index < 3 ? segment : regenerated - 3 * segment
                    try decodeStream(table, stream, count: size, into: literals + index * segment, length: length)
                    stream += size
                }
            }
            return (regenerated, header + compressed)
        }
    }

    private func decodeStream(_ table: HuffmanTable, _ source: UnsafePointer<UInt8>, count: Int,
                              into target: UnsafeMutablePointer<UInt8>, length: Int) throws {
        var bits = try BackwardBits(source, count: count)
        let maxBits = table.maxBits
        table.entries.withUnsafeBufferPointer { buffer in
            guard let entries = buffer.baseAddress else { return }
            var index = 0
            // Most of a log is literals. While a whole word lies before the
            // next bit, one load serves four codes of at most 11 bits each.
            let drop = UInt64(64 - maxBits)
            while length - index >= 4, bits.position >= 64 {
                let last = (bits.position - 1) &>> 3
                var word = UInt64(littleEndian: UnsafeRawPointer(source + (last - 7)).loadUnaligned(as: UInt64.self))
                word &<<= UInt64(7 - ((bits.position - 1) & 7))
                var entry = entries[Int(truncatingIfNeeded: word &>> drop)]
                target[index] = UInt8(truncatingIfNeeded: entry)
                var used = Int(entry &>> 8)
                word &<<= UInt64(entry &>> 8)
                entry = entries[Int(truncatingIfNeeded: word &>> drop)]
                target[index + 1] = UInt8(truncatingIfNeeded: entry)
                used &+= Int(entry &>> 8)
                word &<<= UInt64(entry &>> 8)
                entry = entries[Int(truncatingIfNeeded: word &>> drop)]
                target[index + 2] = UInt8(truncatingIfNeeded: entry)
                used &+= Int(entry &>> 8)
                word &<<= UInt64(entry &>> 8)
                entry = entries[Int(truncatingIfNeeded: word &>> drop)]
                target[index + 3] = UInt8(truncatingIfNeeded: entry)
                used &+= Int(entry &>> 8)
                bits.position &-= used
                index &+= 4
            }
            while index < length {
                let entry = entries[bits.peek(maxBits)]
                target[index] = UInt8(truncatingIfNeeded: entry)
                bits.position -= Int(entry >> 8)
                index += 1
            }
        }
        guard bits.position == 0 else { throw AgentZstd.Failure.corrupt }
    }

    private func decodeSequences(_ source: UnsafePointer<UInt8>, count: Int, literalCount: Int) throws {
        guard count >= 1 else { throw AgentZstd.Failure.truncated }
        var at = 0
        let first = Int(source[0])
        let sequences: Int
        if first < 128 {
            sequences = first
            at = 1
        } else if first < 255 {
            guard count >= 2 else { throw AgentZstd.Failure.truncated }
            sequences = ((first - 128) << 8) + Int(source[1])
            at = 2
        } else {
            guard count >= 3 else { throw AgentZstd.Failure.truncated }
            sequences = Int(source[1]) + (Int(source[2]) << 8) + 0x7F00
            at = 3
        }
        let blockEnd = written + AgentZstd.blockMaximum
        guard sequences > 0 else {
            guard at == count, written + literalCount <= blockEnd else { throw AgentZstd.Failure.corrupt }
            memcpy(buffer + written, literals, literalCount)
            written += literalCount
            return
        }
        guard at < count else { throw AgentZstd.Failure.truncated }
        let modes = Int(source[at])
        at += 1
        guard modes & 3 == 0 else { throw AgentZstd.Failure.corrupt }
        func table(_ mode: Int, previous: FSETable?, predefined: FSETable, maxLog: Int, maxSymbol: Int) throws -> FSETable {
            switch mode {
            case 0:
                return predefined
            case 1:
                guard at < count else { throw AgentZstd.Failure.truncated }
                let symbol = source[at]
                at += 1
                guard Int(symbol) <= maxSymbol else { throw AgentZstd.Failure.corrupt }
                return FSETable(single: symbol)
            case 2:
                let read = try FSETable.read(source + at, count: count - at, maxLog: maxLog, maxSymbol: maxSymbol)
                at += read.used
                return read.table
            default:
                guard let previous else { throw AgentZstd.Failure.corrupt }
                return previous
            }
        }
        let literalTable = try table(modes >> 6, previous: literalLengths, predefined: .literalLengths, maxLog: 9, maxSymbol: 35)
        let offsetTable = try table((modes >> 4) & 3, previous: offsets, predefined: .offsets, maxLog: 8, maxSymbol: 31)
        let matchTable = try table((modes >> 2) & 3, previous: matchLengths, predefined: .matchLengths, maxLog: 9, maxSymbol: 52)
        literalLengths = literalTable
        offsets = offsetTable
        matchLengths = matchTable
        guard at < count else { throw AgentZstd.Failure.truncated }
        var bits = try BackwardBits(source + at, count: count - at)
        var out = written
        var literal = 0
        var (recent, second, third) = repeats
        let literalBase = Frame.literalBase, literalBits = Frame.literalBits
        let matchBase = Frame.matchBase, matchBits = Frame.matchBits
        let buffer = self.buffer
        let literals = self.literals
        try literalTable.entries.withUnsafeBufferPointer { literalEntries in
            try offsetTable.entries.withUnsafeBufferPointer { offsetEntries in
                try matchTable.entries.withUnsafeBufferPointer { matchEntries in
                    var literalState = bits.read(literalTable.log)
                    var offsetState = bits.read(offsetTable.log)
                    var matchState = bits.read(matchTable.log)
                    for index in 0..<sequences {
                        let literalEntry = literalEntries[literalState]
                        let offsetEntry = offsetEntries[offsetState]
                        let matchEntry = matchEntries[matchState]
                        let offsetCode = Int(offsetEntry.symbol)
                        let matchCode = Int(matchEntry.symbol)
                        let literalCode = Int(literalEntry.symbol)
                        let offsetValue = (1 << offsetCode) + bits.read(offsetCode)
                        let matchLength = matchBase[matchCode] + bits.read(matchBits[matchCode])
                        let literalLength = literalBase[literalCode] + bits.read(literalBits[literalCode])
                        if index + 1 < sequences {
                            literalState = Int(literalEntry.base) + bits.read(Int(literalEntry.bits))
                            matchState = Int(matchEntry.base) + bits.read(Int(matchEntry.bits))
                            offsetState = Int(offsetEntry.base) + bits.read(Int(offsetEntry.bits))
                        }
                        let offset: Int
                        if offsetValue > 3 {
                            offset = offsetValue - 3
                            third = second
                            second = recent
                            recent = offset
                        } else {
                            switch offsetValue - (literalLength == 0 ? 0 : 1) {
                            case 0:
                                offset = recent
                            case 1:
                                offset = second
                                second = recent
                                recent = offset
                            case 2:
                                offset = third
                                third = second
                                second = recent
                                recent = offset
                            default:
                                offset = recent - 1
                                third = second
                                second = recent
                                recent = offset
                            }
                        }
                        guard literalLength <= literalCount - literal,
                              literalLength + matchLength <= blockEnd - out else { throw AgentZstd.Failure.corrupt }
                        memcpy(buffer + out, literals + literal, literalLength)
                        out += literalLength
                        literal += literalLength
                        guard offset > 0, offset <= out else { throw AgentZstd.Failure.corrupt }
                        Frame.copyMatch(buffer + out, distance: offset, length: matchLength)
                        out += matchLength
                    }
                }
            }
        }
        let rest = literalCount - literal
        guard rest <= blockEnd - out, bits.position == 0 else { throw AgentZstd.Failure.corrupt }
        memcpy(buffer + out, literals + literal, rest)
        written = out + rest
        repeats = (recent, second, third)
    }

    /// Copies a match that may overlap what it writes: a short distance
    /// repeats its bytes, copied in runs that double each time.
    private static func copyMatch(_ target: UnsafeMutablePointer<UInt8>, distance: Int, length: Int) {
        if distance >= length {
            memcpy(target, target - distance, length)
            return
        }
        var done = 0
        var span = distance
        while done < length {
            let run = min(span, length - done)
            memcpy(target + done, target + done - span, run)
            done += run
            span += run
        }
    }
}
