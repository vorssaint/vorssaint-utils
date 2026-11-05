// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Accelerate
import Foundation

/// Writes MPEG-1 Layer III audio, the format people mean by MP3.
///
/// macOS plays MP3 but ships no encoder for it, and Vorssaint takes no external
/// dependencies, so the format is written here. The structure follows the
/// Shine encoder: constant bitrate, long blocks only and no psychoacoustic
/// model, so each granule is quantized with one step size, the finest the
/// bitrate can pay for. Two choices make up for the missing model. The channels
/// of a granule share that step, so a quiet channel hands its bits to a busy
/// one, and content above what the bitrate can carry is dropped before it
/// competes for bits with what people actually hear. The standard's tables
/// live in `MediaMP3Tables`.
final class MediaMP3Encoder {
    enum ConfigurationError: Error, Equatable {
        case unsupportedSampleRate
        case unsupportedBitRate
        case unsupportedChannelCount
    }

    static let samplesPerFrame = 1152
    /// In the order of the header's sampling_frequency field.
    static let sampleRates = [44_100, 48_000, 32_000]
    /// Kilobits per second, in the order of the header's bitrate_index from 1.
    static let bitRates = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]

    let sampleRate: Int
    let channelCount: Int
    let bitRate: Int

    private static let granuleSize = 576
    private static let maximumQuantized: Int32 = 15 + 8191
    /// part2_3_length is a 12-bit field.
    private static let maximumGranuleBits = 4095
    private static let smallestStep = -210
    private static let largestStep = 45

    private let sampleRateIndex: Int
    private let bitRateIndex: Int
    private let bands: [Int]
    private let lowpassLine: Int
    private let sideInfoBits: Int
    private var analyses: [Analysis]
    private var pending: [[Float]]
    private var paddingRemainder = 0
    private var framesWritten = 0
    /// The step the previous granule settled on, where the next search starts.
    private var lastStep = 0

    init(sampleRate: Int, channelCount: Int, bitRate: Int) throws {
        guard let sampleRateIndex = Self.sampleRates.firstIndex(of: sampleRate) else {
            throw ConfigurationError.unsupportedSampleRate
        }
        guard let bitRateIndex = Self.bitRates.firstIndex(of: bitRate) else {
            throw ConfigurationError.unsupportedBitRate
        }
        guard channelCount == 1 || channelCount == 2 else {
            throw ConfigurationError.unsupportedChannelCount
        }
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bitRate = bitRate
        self.sampleRateIndex = sampleRateIndex
        self.bitRateIndex = bitRateIndex + 1
        bands = MediaMP3Tables.longBlockBands[sampleRateIndex]
        let perChannel = Double(bitRate) / Double(channelCount)
        let cutoff = min(20_000, max(8_000, 16_000 + (perChannel - 64) * 62.5))
        lowpassLine = min(Self.granuleSize,
                          Int((cutoff / (Double(sampleRate) / 2) * Double(Self.granuleSize)).rounded()))
        sideInfoBits = channelCount == 1 ? 136 : 256
        analyses = Array(repeating: Analysis(), count: channelCount)
        pending = Array(repeating: [], count: channelCount)
    }

    /// Takes interleaved samples in -1...1 and returns the frames they complete.
    func encode(interleaved samples: UnsafeBufferPointer<Float>) -> Data {
        let frames = samples.count / channelCount
        guard frames > 0, let base = samples.baseAddress else { return drain() }
        for channel in 0..<channelCount {
            // A strided copy pulls one channel out of the interleaved buffer.
            let channelSamples = [Float](unsafeUninitializedCapacity: frames) { buffer, count in
                vDSP_mmov(base + channel, buffer.baseAddress!, 1, vDSP_Length(frames),
                          vDSP_Length(channelCount), 1)
                count = frames
            }
            pending[channel].append(contentsOf: channelSamples)
        }
        return drain()
    }

    /// Ends the stream. The filterbank holds back about one frame of samples,
    /// so a frame of silence follows the last partial one to bring them out.
    /// Players recognize MP3 by two consecutive frames, so even an empty
    /// stream ends with two.
    func finish() -> Data {
        let remainder = pending[0].count % Self.samplesPerFrame
        var padding = (remainder == 0 ? 0 : Self.samplesPerFrame - remainder) + Self.samplesPerFrame
        if framesWritten + (pending[0].count + padding) / Self.samplesPerFrame < 2 {
            padding += Self.samplesPerFrame
        }
        for channel in 0..<channelCount {
            pending[channel].append(contentsOf: repeatElement(0, count: padding))
        }
        return drain()
    }

    private func drain() -> Data {
        var output = Data()
        var offset = 0
        while pending[0].count - offset >= Self.samplesPerFrame {
            output.append(contentsOf: encodeFrame(at: offset))
            offset += Self.samplesPerFrame
            framesWritten += 1
        }
        if offset > 0 {
            for channel in 0..<channelCount { pending[channel].removeFirst(offset) }
        }
        return output
    }

    // MARK: - Frame

    private func encodeFrame(at offset: Int) -> [UInt8] {
        let unit = 144_000 * bitRate
        paddingRemainder += unit % sampleRate
        let padding = paddingRemainder >= sampleRate ? 1 : 0
        paddingRemainder -= padding * sampleRate
        let frameBytes = unit / sampleRate + padding
        let mainBits = frameBytes * 8 - 32 - sideInfoBits

        var spectra = [[[Float]]](repeating: [[Float]](repeating: [], count: channelCount), count: 2)
        for channel in 0..<channelCount {
            pending[channel].withUnsafeBufferPointer { samples in
                for granule in 0..<2 {
                    var lines = analyses[channel].granule(samples.baseAddress! + offset + granule * Self.granuleSize)
                    lines.withUnsafeMutableBufferPointer { buffer in
                        vDSP_vclr(buffer.baseAddress! + lowpassLine, 1,
                                  vDSP_Length(Self.granuleSize - lowpassLine))
                    }
                    spectra[granule][channel] = lines
                }
            }
        }

        let midSide = channelCount == 2 && prefersMidSide(spectra)
        if midSide {
            var scale = Float(0.5.squareRoot())
            let count = vDSP_Length(Self.granuleSize)
            for granule in 0..<2 {
                let left = spectra[granule][0], right = spectra[granule][1]
                var sum = [Float](repeating: 0, count: Self.granuleSize)
                var difference = sum
                vDSP_vadd(left, 1, right, 1, &sum, 1, count)
                vDSP_vsub(right, 1, left, 1, &difference, 1, count)
                vDSP_vsmul(sum, 1, &scale, &spectra[granule][0], 1, count)
                vDSP_vsmul(difference, 1, &scale, &spectra[granule][1], 1, count)
            }
        }

        var codings: [[Coding]] = []
        var quantized: [[[Int32]]] = []
        var remaining = mainBits
        for granule in 0..<2 {
            let budget = granule == 0 ? mainBits / 2 : remaining
            let (granuleCodings, granuleValues) = allocate(spectra[granule], budget: budget)
            remaining -= granuleCodings.reduce(0) { $0 + $1.bits }
            codings.append(granuleCodings)
            quantized.append(granuleValues)
        }

        var main: [[BitWriter]] = []
        for granule in 0..<2 {
            var row: [BitWriter] = []
            for channel in 0..<channelCount {
                var writer = BitWriter()
                writeMainData(quantized[granule][channel], signs: spectra[granule][channel],
                              coding: codings[granule][channel], to: &writer)
                codings[granule][channel].bits = writer.bitCount
                row.append(writer)
            }
            main.append(row)
        }

        var frame = BitWriter()
        writeHeader(padding: padding, midSide: midSide, to: &frame)
        writeSideInfo(codings, to: &frame)
        for granule in 0..<2 {
            for channel in 0..<channelCount { frame.append(main[granule][channel]) }
        }
        // Whatever the granules left unused is ancillary data, which decoders
        // skip because the next frame's main data begins at its own header.
        frame.pad(toBits: frameBytes * 8)
        return frame.bytes
    }

    /// Mid/side pays off when the channels are alike, because the side channel
    /// then carries little and costs few bits. Coding cost grows with the log
    /// of each band's energy, so the layout with the smaller summed log wins.
    private func prefersMidSide(_ spectra: [[[Float]]]) -> Bool {
        var energies = [[Double]](repeating: [Double](repeating: 0, count: 4), count: bands.count - 1)
        let count = vDSP_Length(Self.granuleSize)
        for granule in 0..<2 {
            let left = spectra[granule][0], right = spectra[granule][1]
            var sum = [Float](repeating: 0, count: Self.granuleSize)
            var difference = sum
            vDSP_vadd(left, 1, right, 1, &sum, 1, count)
            vDSP_vsub(right, 1, left, 1, &difference, 1, count)
            // Mid and side are the sum and difference scaled by 1/sqrt(2),
            // which halves their energy.
            for (layout, signal) in [(0, left), (1, right), (2, sum), (3, difference)] {
                let scale = layout < 2 ? 1.0 : 0.5
                signal.withUnsafeBufferPointer { buffer in
                    for band in 0..<(bands.count - 1) {
                        var energy: Float = 0
                        vDSP_svesq(buffer.baseAddress! + bands[band], 1, &energy,
                                   vDSP_Length(bands[band + 1] - bands[band]))
                        energies[band][layout] += Double(energy) * scale
                    }
                }
            }
        }
        var peak = 0.0
        for band in 0..<(bands.count - 1) {
            peak = max(peak, energies[band].max()! / Double(bands[band + 1] - bands[band]))
        }
        guard peak > 0 else { return false }
        let floor = peak * 1e-7
        var separate = 0.0, joint = 0.0
        for band in 0..<(bands.count - 1) {
            let width = Double(bands[band + 1] - bands[band])
            func cost(_ energy: Double) -> Double { width * log2(energy / width + floor) }
            separate += cost(energies[band][0]) + cost(energies[band][1])
            joint += cost(energies[band][2]) + cost(energies[band][3])
        }
        return joint < separate
    }

    // MARK: - Rate control

    /// Finds the finest step at which every channel of the granule fits the
    /// shared budget, so quantization noise sits at one level in all of them.
    private func allocate(_ spectra: [[Float]], budget: Int) -> ([Coding], [[Int32]]) {
        // The quantizer works on |x|^(3/4), the square root of |x| * sqrt|x|.
        let count = vDSP_Length(Self.granuleSize)
        var length = Int32(Self.granuleSize)
        let magnitudes = spectra.map { lines -> [Float] in
            var absolute = [Float](repeating: 0, count: Self.granuleSize)
            var root = absolute, product = absolute, result = absolute
            vDSP_vabs(lines, 1, &absolute, 1, count)
            vvsqrtf(&root, absolute, &length)
            vDSP_vmul(absolute, 1, root, 1, &product, 1, count)
            vvsqrtf(&result, product, &length)
            return result
        }
        let peaks = magnitudes.map { magnitude -> Float in
            var peak: Float = 0
            vDSP_maxv(magnitude, 1, &peak, count)
            return peak
        }
        var values = [[Int32]](repeating: [Int32](repeating: 0, count: Self.granuleSize), count: spectra.count)
        let silent = [Coding](repeating: Coding(), count: spectra.count)

        var evaluatedStep: Int?
        var evaluatedCodings: [Coding]?
        func evaluate(_ step: Int) -> [Coding]? {
            let scale = Float(exp2(-0.1875 * Double(step)))
            var codings: [Coding]? = silent
            var total = 0
            for channel in spectra.indices where peaks[channel] > 0 {
                guard peaks[channel] * scale + 0.4054 < Float(Self.maximumQuantized) + 1 else {
                    codings = nil
                    break
                }
                magnitudes[channel].withUnsafeBufferPointer { source in
                    values[channel].withUnsafeMutableBufferPointer { target in
                        var line = 0
                        while line < Self.granuleSize {
                            target[line] = Int32(source[line] * scale + 0.4054)
                            line += 1
                        }
                    }
                }
                var coding = code(values[channel])
                guard coding.bits <= Self.maximumGranuleBits else {
                    codings = nil
                    break
                }
                coding.globalGain = step + 210
                codings?[channel] = coding
                total += coding.bits
            }
            if total > budget { codings = nil }
            evaluatedStep = step
            evaluatedCodings = codings
            return codings
        }

        let silence = (silent, [[Int32]](repeating: [Int32](repeating: 0, count: Self.granuleSize),
                                         count: spectra.count))
        guard peaks.contains(where: { $0 > 0 }) else { return silence }
        // Neighbouring granules almost always need nearly the same step, so
        // the search starts from the last one and widens only as far as it
        // must, instead of bisecting all 256 steps every time. `upper` always
        // fits; `lower` never does, or lies below the smallest step.
        let start = min(max(lastStep, Self.smallestStep), Self.largestStep)
        var lower: Int
        var upper: Int
        var reach = 1
        if evaluate(start) != nil {
            upper = start
            lower = start - 1
            while lower >= Self.smallestStep, evaluate(lower) != nil {
                upper = lower
                reach *= 2
                lower = upper - reach
            }
            lower = max(lower, Self.smallestStep - 1)
        } else {
            lower = start
            upper = start + 1
            while upper <= Self.largestStep, evaluate(upper) == nil {
                lower = upper
                reach *= 2
                upper = lower + reach
            }
            if upper > Self.largestStep {
                guard lower < Self.largestStep, evaluate(Self.largestStep) != nil else { return silence }
                upper = Self.largestStep
            }
        }
        while upper - lower > 1 {
            let middle = lower + (upper - lower) / 2
            if evaluate(middle) != nil { upper = middle } else { lower = middle }
        }
        // The values buffer holds whichever step was tried last, so it is
        // rebuilt only when that was not the step chosen.
        let codings: [Coding]
        if evaluatedStep == upper, let kept = evaluatedCodings {
            codings = kept
        } else {
            codings = evaluate(upper)!
        }
        lastStep = upper
        for channel in spectra.indices where peaks[channel] == 0 {
            values[channel] = [Int32](repeating: 0, count: Self.granuleSize)
        }
        return (codings, values)
    }

    /// Partitions quantized values into the big-value pairs, the count1
    /// quadruples and the zero tail, picks tables, and counts the bits.
    private func code(_ values: [Int32]) -> Coding {
        values.withUnsafeBufferPointer { code($0) }
    }

    // The counting below runs for every step the search tries, so it reads
    // the values through a raw buffer and in plain loops; debug builds would
    // otherwise spend most of a conversion in array and range bookkeeping.
    private func code(_ values: UnsafeBufferPointer<Int32>) -> Coding {
        var coding = Coding()
        var end = Self.granuleSize
        while end > 1, values[end - 1] == 0, values[end - 2] == 0 { end -= 2 }
        var start = end
        while start > 3, values[start - 1] <= 1, values[start - 2] <= 1,
              values[start - 3] <= 1, values[start - 4] <= 1 {
            start -= 4
        }
        coding.bigValues = start / 2
        coding.count1 = (end - start) / 4

        var bitsA = 0, bitsB = 0
        var base = start
        while base < end {
            let index = Int(values[base] << 3 | values[base + 1] << 2 | values[base + 2] << 1 | values[base + 3])
            let signs = Int(values[base] + values[base + 1] + values[base + 2] + values[base + 3])
            bitsA += Int(Self.count1A.lengths[index]) + signs
            bitsB += 4 + signs
            base += 4
        }
        coding.count1Table = bitsB < bitsA ? 1 : 0

        let pairs = coding.bigValues * 2
        if pairs > 0 {
            var bandCount = 0
            while bands[bandCount] < pairs { bandCount += 1 }
            var region0 = Self.region0Counts[bandCount]
            while region0 > 0, bands[region0 + 1] > pairs { region0 -= 1 }
            var region1 = Self.region1Counts[bandCount]
            while region1 > 0, bands[region0 + region1 + 2] > pairs { region1 -= 1 }
            coding.region0Count = region0
            coding.region1Count = region1
        }
        let (first, second) = regionBoundaries(coding)
        let low = chooseTable(values, 0, first)
        let middle = chooseTable(values, first, second)
        let high = chooseTable(values, second, pairs)
        coding.tables = [low.table, middle.table, high.table]
        coding.bits = min(bitsA, bitsB) + low.bits + middle.bits + high.bits
        return coding
    }

    /// Where regions 1 and 2 start, as the decoder derives them, cut off where
    /// the big values end so a region past them is empty rather than miscounted.
    private func regionBoundaries(_ coding: Coding) -> (Int, Int) {
        let pairs = coding.bigValues * 2
        return (min(pairs, bands[coding.region0Count + 1]),
                min(pairs, bands[coding.region0Count + coding.region1Count + 2]))
    }

    private func chooseTable(_ values: UnsafeBufferPointer<Int32>, _ begin: Int, _ end: Int) -> (table: Int, bits: Int) {
        var peak: Int32 = 0
        var index = begin
        while index < end {
            if values[index] > peak { peak = values[index] }
            index += 1
        }
        guard peak > 0 else { return (0, 0) }
        let candidates: [Int]
        if peak < 15 {
            candidates = Self.smallTables[Int(peak)]
        } else {
            let escape = Int(peak) - 15
            candidates = Self.escapeTables[escape == 0 ? 0 : Int.bitWidth - escape.leadingZeroBitCount]
        }
        var best = (table: 0, bits: Int.max)
        for table in candidates {
            let bits = countBits(values, begin, end, table: table)
            if bits < best.bits { best = (table, bits) }
        }
        return best
    }

    private func countBits(_ values: UnsafeBufferPointer<Int32>, _ begin: Int, _ end: Int, table: Int) -> Int {
        let book = Self.codebooks[table]!
        var bits = 0
        var index = begin
        book.lengths.withUnsafeBufferPointer { lengths in
            while index < end {
                var x = Int(values[index]), y = Int(values[index + 1])
                if book.linbits > 0 {
                    if x > 14 { x = 15; bits += book.linbits }
                    if y > 14 { y = 15; bits += book.linbits }
                }
                bits += Int(lengths[x * book.size + y])
                if x != 0 { bits += 1 }
                if y != 0 { bits += 1 }
                index += 2
            }
        }
        return bits
    }

    // MARK: - Bitstream

    private func writeHeader(padding: Int, midSide: Bool, to writer: inout BitWriter) {
        writer.write(0x7FF, 11)          // sync
        writer.write(0b11, 2)            // MPEG-1
        writer.write(0b01, 2)            // Layer III
        writer.write(1, 1)               // no CRC
        writer.write(UInt32(bitRateIndex), 4)
        writer.write(UInt32(sampleRateIndex), 2)
        writer.write(UInt32(padding), 1)
        writer.write(0, 1)               // private
        writer.write(channelCount == 1 ? 0b11 : 0b01, 2)   // mono or joint stereo
        writer.write(midSide ? 0b10 : 0b00, 2)              // mid/side on, intensity off
        writer.write(0, 1)               // copyright
        writer.write(1, 1)               // original
        writer.write(0, 2)               // no emphasis
    }

    private func writeSideInfo(_ codings: [[Coding]], to writer: inout BitWriter) {
        writer.write(0, 9)                                // main_data_begin: no reservoir
        writer.write(0, channelCount == 1 ? 5 : 3)        // private bits
        writer.write(0, 4 * channelCount)                 // scfsi
        for granule in 0..<2 {
            for channel in 0..<channelCount {
                let coding = codings[granule][channel]
                writer.write(UInt32(coding.bits), 12)     // part2_3_length
                writer.write(UInt32(coding.bigValues), 9)
                writer.write(UInt32(coding.globalGain), 8)
                writer.write(0, 4)                        // scalefac_compress: no scalefactors
                writer.write(0, 1)                        // window_switching_flag: long blocks
                for region in 0..<3 { writer.write(UInt32(coding.tables[region]), 5) }
                writer.write(UInt32(coding.region0Count), 4)
                writer.write(UInt32(coding.region1Count), 3)
                writer.write(0, 1)                        // preflag
                writer.write(0, 1)                        // scalefac_scale
                writer.write(UInt32(coding.count1Table), 1)
            }
        }
    }

    private func writeMainData(_ values: [Int32], signs: [Float], coding: Coding, to writer: inout BitWriter) {
        let (first, second) = regionBoundaries(coding)
        let books = coding.tables.map { Self.codebooks[$0] }
        var index = 0
        while index < coding.bigValues * 2 {
            let region = index < first ? 0 : (index < second ? 1 : 2)
            if let book = books[region] {
                writePair(Int(values[index]), signs[index] < 0, Int(values[index + 1]), signs[index + 1] < 0,
                          book: book, to: &writer)
            }
            index += 2
        }
        let book = coding.count1Table == 0 ? Self.count1A : Self.count1B
        for _ in 0..<coding.count1 {
            let code = Int(values[index] << 3 | values[index + 1] << 2 | values[index + 2] << 1 | values[index + 3])
            writer.write(UInt32(book.codes[code]), Int(book.lengths[code]))
            for offset in 0..<4 where values[index + offset] != 0 {
                writer.write(signs[index + offset] < 0 ? 1 : 0, 1)
            }
            index += 4
        }
    }

    private func writePair(_ x: Int, _ xNegative: Bool, _ y: Int, _ yNegative: Bool,
                           book: MediaMP3Tables.Codebook, to writer: inout BitWriter) {
        let escapedX = book.linbits > 0 && x > 14
        let escapedY = book.linbits > 0 && y > 14
        let index = (escapedX ? 15 : x) * book.size + (escapedY ? 15 : y)
        writer.write(UInt32(book.codes[index]), Int(book.lengths[index]))
        if escapedX { writer.write(UInt32(x - 15), book.linbits) }
        if x != 0 { writer.write(xNegative ? 1 : 0, 1) }
        if escapedY { writer.write(UInt32(y - 15), book.linbits) }
        if y != 0 { writer.write(yNegative ? 1 : 0, 1) }
    }

    // MARK: - Tables

    private struct Coding {
        var bits = 0
        var bigValues = 0
        var count1 = 0
        var count1Table = 0
        var globalGain = 210
        var tables = [0, 0, 0]
        var region0Count = 0
        var region1Count = 0
    }

    private static let codebooks = MediaMP3Tables.codebooks
    private static let count1A = codebooks[32]!
    private static let count1B = codebooks[33]!
    private static let region0Counts = MediaMP3Tables.regionCounts.map { $0.0 }
    private static let region1Counts = MediaMP3Tables.regionCounts.map { $0.1 }

    /// Tables to try for big values up to 14, by the largest value: the
    /// smallest codebooks that can hold it.
    private static let smallTables: [[Int]] = (0...14).map { peak in
        switch peak {
        case 0: return []
        case 1: return [1]
        case 2: return [2, 3]
        case 3: return [5, 6]
        case 4, 5: return [7, 8, 9]
        case 6, 7: return [10, 11, 12]
        default: return [13, 15]
        }
    }

    /// The two escape tables to try, one from each family, by how many bits
    /// the largest value's excess over 15 needs.
    private static let escapeTables: [[Int]] = (0...13).map { needed in
        [(16...23).first { codebooks[$0]!.linbits >= needed }!,
         (24...31).first { codebooks[$0]!.linbits >= needed }!]
    }
}

// MARK: - Analysis

private extension MediaMP3Encoder {
    /// One channel's polyphase filterbank and MDCT, carried across frames.
    struct Analysis {
        /// The last 512 samples, newest first, as the standard's X vector.
        private var history = [Float](repeating: 0, count: 512)
        /// Subband samples of the previous granule (rows 0 to 17) and the
        /// current one (rows 18 to 35), one row of 32 bands per time slot.
        /// Each column is then exactly the 36 inputs of that band's MDCT.
        private var timeline = [Float](repeating: 0, count: 36 * 32)
        private var windowed = [Float](repeating: 0, count: 512)
        private var folded = [Float](repeating: 0, count: 64)
        private var transformed = [Float](repeating: 0, count: 18 * 32)

        /// Turns 576 samples into 576 frequency lines, [band * 18 + line].
        mutating func granule(_ samples: UnsafePointer<Float>) -> [Float] {
            for time in 0..<18 {
                history.withUnsafeMutableBufferPointer { buffer in
                    let base = buffer.baseAddress!
                    memmove(base + 32, base, 480 * MemoryLayout<Float>.stride)
                    memcpy(base, samples + time * 32, 32 * MemoryLayout<Float>.stride)
                    vDSP_vrvrs(base, 1, 32)
                }
                vDSP_vmul(history, 1, Filter.window, 1, &windowed, 1, 512)
                vDSP_mmul(Filter.ones, 1, windowed, 1, &folded, 1, 1, 64, 8)
                timeline.withUnsafeMutableBufferPointer { buffer in
                    let row = buffer.baseAddress! + (18 + time) * 32
                    vDSP_mmul(Filter.polyphase, 1, folded, 1, row, 1, 32, 1, 64)
                    // The filterbank inverts the spectrum of every odd band;
                    // negating its odd samples puts the lines back in order.
                    if time % 2 == 1 {
                        for band in stride(from: 1, to: 32, by: 2) { row[band] = -row[band] }
                    }
                }
            }

            // Every band's MDCT at once: 18 lines by 32 bands, transposed to
            // the band-major order the rest of the encoder reads.
            vDSP_mmul(Filter.mdct, 1, timeline, 1, &transformed, 1, 18, 32, 36)
            var lines = [Float](repeating: 0, count: 576)
            vDSP_mtrans(transformed, 1, &lines, 1, 32, 18)
            timeline.withUnsafeMutableBufferPointer { buffer in
                let base = buffer.baseAddress!
                memmove(base, base + 18 * 32, 18 * 32 * MemoryLayout<Float>.stride)
            }

            // Undo the aliasing between neighbouring bands that the decoder
            // will reintroduce, butterfly by butterfly (Table B.9).
            let cs = Filter.aliasCS, ca = Filter.aliasCA
            lines.withUnsafeMutableBufferPointer { buffer in
                let lines = buffer.baseAddress!
                var band = 1
                while band < 32 {
                    var index = 0
                    while index < 8 {
                        let upper = (band - 1) * 18 + 17 - index
                        let lower = band * 18 + index
                        let up = lines[upper], down = lines[lower]
                        lines[upper] = up * cs[index] + down * ca[index]
                        lines[lower] = down * cs[index] - up * ca[index]
                        index += 1
                    }
                    band += 1
                }
            }
            return lines
        }
    }

    enum Filter {
        static let window = MediaMP3Tables.analysisWindow
        static let ones = [Float](repeating: 1, count: 8)

        /// M[i][k] = cos((2i + 1)(16 - k) pi / 64), 32 rows of 64.
        static let polyphase: [Float] = {
            var matrix = [Float](repeating: 0, count: 32 * 64)
            for band in 0..<32 {
                for tap in 0..<64 {
                    let angle = Double((2 * band + 1) * (16 - tap)) * Double.pi / 64
                    matrix[band * 64 + tap] = Float(cos(angle))
                }
            }
            return matrix
        }()

        /// The sine-windowed long-block MDCT, 18 rows of 36. Divided by 9, half
        /// the 18 lines, because the decoder's inverse transform carries no scale.
        static let mdct: [Float] = {
            var matrix = [Float](repeating: 0, count: 18 * 36)
            for line in 0..<18 {
                for time in 0..<36 {
                    let window = sin(Double.pi / 36 * (Double(time) + 0.5))
                    let angle = Double.pi / 72 * Double((2 * time + 19) * (2 * line + 1))
                    matrix[line * 36 + time] = Float(window * cos(angle) / 9)
                }
            }
            return matrix
        }()

        static let aliasCoefficients: [Double] = [-0.6, -0.535, -0.33, -0.185, -0.095, -0.041, -0.0142, -0.0037]
        static let aliasCS = aliasCoefficients.map { Float(1 / (1 + $0 * $0).squareRoot()) }
        static let aliasCA = aliasCoefficients.map { Float($0 / (1 + $0 * $0).squareRoot()) }
    }

    /// Packs bits most significant first, as MPEG streams are written.
    struct BitWriter {
        private(set) var bytes: [UInt8] = []
        private var accumulator: UInt64 = 0
        private var pendingBits = 0

        var bitCount: Int { bytes.count * 8 + pendingBits }

        mutating func write(_ value: UInt32, _ count: Int) {
            guard count > 0 else { return }
            accumulator = accumulator << UInt64(count) | UInt64(value) & ((1 << UInt64(count)) - 1)
            pendingBits += count
            while pendingBits >= 8 {
                pendingBits -= 8
                bytes.append(UInt8(truncatingIfNeeded: accumulator >> UInt64(pendingBits)))
            }
            accumulator &= (1 << UInt64(pendingBits)) - 1
        }

        mutating func append(_ other: BitWriter) {
            // Four bytes per write: the frame is rarely byte aligned here, so
            // the bits have to pass through the accumulator either way.
            var index = 0
            while index + 4 <= other.bytes.count {
                let word = UInt32(other.bytes[index]) << 24 | UInt32(other.bytes[index + 1]) << 16
                    | UInt32(other.bytes[index + 2]) << 8 | UInt32(other.bytes[index + 3])
                write(word, 32)
                index += 4
            }
            while index < other.bytes.count {
                write(UInt32(other.bytes[index]), 8)
                index += 1
            }
            write(UInt32(other.accumulator), other.pendingBits)
        }

        mutating func pad(toBits total: Int) {
            while bitCount < total { write(0, min(8, total - bitCount)) }
        }
    }
}
