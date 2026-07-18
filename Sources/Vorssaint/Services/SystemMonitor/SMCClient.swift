// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

/// Minimal client for the System Management Controller (AppleSMC), used to read
/// temperature sensors on Apple Silicon. Speaks the public SMCParamStruct ABI
/// through IOConnectCallStructMethod — the same mechanism used by Activity
/// Monitor-style tools.
final class SMCClient {
    struct Key {
        let code: UInt32
        let name: String
        let dataSize: UInt32
        let dataType: String
    }

    private var connection: io_connect_t = 0

    // Selector and command bytes of the SMC user client.
    private static let handleYPCEvent: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdKeyFromIndex: UInt8 = 8
    private static let cmdKeyInfo: UInt8 = 9

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: - Key discovery

    /// Enumerates every SMC key whose name passes `filter`. Done once at startup;
    /// the resulting keys are then read directly on each refresh.
    func keys(where filter: (String) -> Bool) -> [Key] {
        var result: [Key] = []
        for index in 0..<keyCount() {
            var probe = SMCParamStruct()
            probe.data8 = Self.cmdKeyFromIndex
            probe.data32 = UInt32(index)
            guard let out = call(&probe), out.result == 0 else { continue }

            let name = Self.fourCCString(out.key)
            guard filter(name) else { continue }

            var infoIn = SMCParamStruct()
            infoIn.key = out.key
            infoIn.data8 = Self.cmdKeyInfo
            guard let info = call(&infoIn), info.result == 0 else { continue }

            result.append(Key(code: out.key,
                              name: name,
                              dataSize: info.keyInfo.dataSize,
                              dataType: Self.fourCCString(info.keyInfo.dataType)))
        }
        return result
    }

    /// Reads a temperature-style value in the key's native encoding.
    func readValue(_ key: Key) -> Double? {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = key.dataSize
        input.data8 = Self.cmdReadKey
        guard let out = call(&input), out.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(key.dataSize))) }
        let dataType = key.dataType.trimmingCharacters(in: .whitespacesAndNewlines)
        switch dataType {
        case "flt" where bytes.count == 4:
            return Double(bytes.withUnsafeBytes { $0.load(as: Float32.self) })
        case "sp78" where bytes.count == 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256.0
        case "ioft" where bytes.count == 8:
            return Double(bytes.withUnsafeBytes { $0.load(as: UInt64.self) }) / 65536.0
        case "fpe2" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4.0
        case "ui8" where bytes.count == 1:
            return Double(bytes[0])
        case "ui16" where bytes.count == 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "hex" where bytes.count == 1:
            return Double(bytes[0])
        default:
            return nil
        }
    }

    /// Reads a string value from SMC, e.g. for fan labels (F0ID).
    func readStringValue(_ key: Key) -> String? {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = key.dataSize
        input.data8 = Self.cmdReadKey
        guard let out = call(&input), out.result == 0 else { return nil }

        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(key.dataSize))) }
        guard bytes.count > 2 else {
            let printable = bytes.filter { $0 >= 32 && $0 <= 126 }
            return String(bytes: printable, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stringBytes = bytes[2...]
        let printable = stringBytes.prefix(while: { $0 >= 32 && $0 <= 126 })
        if let decoded = String(bytes: printable, encoding: .ascii) {
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    /// Looks up a single key by its 4-character code, returning its size and type
    /// so `readValue` can decode it. Cheaper than enumerating every key — used to
    /// resolve the power sensors directly.
    func key(named name: String) -> Key? {
        var probe = SMCParamStruct()
        probe.key = Self.fourCC(name)
        probe.data8 = Self.cmdKeyInfo
        guard let out = call(&probe), out.result == 0 else { return nil }
        return Key(code: probe.key,
                   name: name,
                   dataSize: out.keyInfo.dataSize,
                   dataType: Self.fourCCString(out.keyInfo.dataType))
    }

    // MARK: - Plumbing

    private func keyCount() -> Int {
        var input = SMCParamStruct()
        input.key = Self.fourCC("#KEY")
        input.keyInfo.dataSize = 4
        input.data8 = Self.cmdReadKey
        guard let out = call(&input), out.result == 0 else { return 0 }
        let b = withUnsafeBytes(of: out.bytes) { Array($0.prefix(4)) }
        return Int(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, Self.handleYPCEvent,
                                           &input, MemoryLayout<SMCParamStruct>.stride,
                                           &output, &outSize)
        return kr == kIOReturnSuccess ? output : nil
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCCString(_ v: UInt32) -> String {
        let chars = [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff),
                     UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        return String(bytes: chars, encoding: .ascii) ?? "????"
    }
}

/// Wire format of the AppleSMC user client (fixed 80-byte layout).
struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

struct SMCVersion {
    var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitData {
    var version: UInt16 = 0, length: UInt16 = 0
    var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
}

struct SMCKeyInfoData {
    var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0
}
