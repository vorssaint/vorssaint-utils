import Darwin
import Foundation

enum AgentDeepSeekLogReader {
    private static let maximumFrame = AgentLogReader.maximumLine
    static var supportsCompression: Bool { Zstd.shared != nil }

    private typealias FindFrameSize = @convention(c) (UnsafeRawPointer?, Int) -> Int
    private typealias Decompress = @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int) -> Int
    private typealias IsError = @convention(c) (Int) -> UInt32

    private struct Zstd {
        let handle: UnsafeMutableRawPointer
        let findFrameSize: FindFrameSize
        let decompress: Decompress
        let isError: IsError

        static let shared: Zstd? = {
            for path in ["/opt/homebrew/lib/libzstd.dylib", "/usr/local/lib/libzstd.dylib"] {
                guard let handle = dlopen(path, RTLD_LAZY) else { continue }
                guard let find = dlsym(handle, "ZSTD_findFrameCompressedSize"),
                      let decompress = dlsym(handle, "ZSTD_decompress"),
                      let isError = dlsym(handle, "ZSTD_isError") else {
                    dlclose(handle)
                    continue
                }
                return Zstd(handle: handle,
                            findFrameSize: unsafeBitCast(find, to: FindFrameSize.self),
                            decompress: unsafeBitCast(decompress, to: Decompress.self),
                            isError: unsafeBitCast(isError, to: IsError.self))
            }
            return nil
        }()
    }

    static func readAppended(_ cursor: AgentLogCursor,
                             shouldContinue: () -> Bool = { true },
                             line: (Data) -> Void) {
        guard shouldContinue(), let zstd = Zstd.shared else { return }
        var info = stat()
        guard stat(cursor.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return }
        let size = UInt64(max(0, info.st_size))
        let identity = UInt64(info.st_ino)
        cursor.modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                               + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        if identity != cursor.identity || size < cursor.offset ||
            (size > cursor.offset && !cursor.holdsWhatWasRead) {
            cursor.startOver(identity: identity)
        }
        defer { cursor.fingerprintRead() }
        guard size > cursor.offset else { return }
        let descriptor = open(cursor.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        var opened = stat()
        guard fstat(descriptor, &opened) == 0, (opened.st_mode & S_IFMT) == S_IFREG,
              UInt64(opened.st_ino) == identity else { return }

        while cursor.offset < size, shouldContinue() {
            let frameStart = cursor.offset
            var compressed = Data()
            var frameSize: Int?
            while frameSize == nil && UInt64(compressed.count) < size - frameStart {
                guard compressed.count < maximumFrame, shouldContinue() else { return }
                let wanted = min(1 << 20, maximumFrame - compressed.count,
                                 Int(min(UInt64(maximumFrame), size - frameStart - UInt64(compressed.count))))
                var chunk = Data(count: wanted)
                let read = chunk.withUnsafeMutableBytes { bytes in
                    pread(descriptor, bytes.baseAddress, wanted, off_t(frameStart + UInt64(compressed.count)))
                }
                guard read > 0 else { return }
                compressed.append(chunk.prefix(read))
                if compressed.count > maximumFrame { return }
                compressed.withUnsafeBytes { bytes in
                    guard frameSize == nil else { return }
                    let value = zstd.findFrameSize(bytes.baseAddress, compressed.count)
                    if zstd.isError(value) == 0, value > 0, value <= compressed.count { frameSize = value }
                }
            }
            guard let frameSize, frameSize <= maximumFrame else { return }
            let frame = compressed.prefix(frameSize)
            var decoded = Data(count: maximumFrame)
            let decodedSize: Int = decoded.withUnsafeMutableBytes { output in
                frame.withUnsafeBytes { input in
                    zstd.decompress(output.baseAddress, maximumFrame, input.baseAddress, frame.count)
                }
            }
            guard decodedSize > 0, decodedSize <= decoded.count, zstd.isError(decodedSize) == 0 else { return }
            decoded.removeSubrange(decodedSize..<decoded.count)
            guard decoded.last == 0x0A else { return }
            deliver(decoded, line: line)
            cursor.offset = frameStart + UInt64(frameSize)
        }
    }

    private static func deliver(_ data: Data, line: (Data) -> Void) {
        var start = 0
        while start < data.count, let newline = data[start...].firstIndex(of: 0x0A) {
            let end = data.distance(from: data.startIndex, to: newline)
            if end > start, end - start <= AgentLogReader.maximumLine {
                line(data.subdata(in: start..<end))
            }
            start = end + 1
        }
    }
}
