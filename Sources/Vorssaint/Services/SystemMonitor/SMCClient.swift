// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit

/// Minimal client for the System Management Controller (AppleSMC). It reads
/// sensors and allows narrowly scoped writes through the SMCParamStruct ABI.
final class SMCClient {
    enum WriteError: Error {
        case invalidPayload
        case unsupportedType
        case transport(kern_return_t)
        case controller(UInt8)
    }

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
    private static let cmdWriteKey: UInt8 = 6
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
        guard let bytes = readBytes(key) else { return nil }
        return SMCValueCodec.decode(bytes, type: key.dataType)
    }

    func readBytes(_ key: Key) -> [UInt8]? {
        guard key.dataSize > 0, key.dataSize <= 32 else { return nil }
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = key.dataSize
        input.data8 = Self.cmdReadKey
        guard let out = call(&input), out.result == 0 else { return nil }
        return withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(key.dataSize))) }
    }

    /// Writes only a value encoded in the key's own reported type and size.
    /// Callers cannot change the key metadata or overrun the fixed SMC payload.
    func writeValue(_ value: Double, to key: Key) throws {
        guard let bytes = SMCValueCodec.encode(value, type: key.dataType,
                                               size: Int(key.dataSize)) else {
            throw WriteError.unsupportedType
        }
        try writeBytes(bytes, to: key)
    }

    func writeBytes(_ bytes: [UInt8], to key: Key) throws {
        guard key.dataSize > 0, key.dataSize <= 32,
              bytes.count == Int(key.dataSize) else {
            throw WriteError.invalidPayload
        }
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = key.dataSize
        input.data8 = Self.cmdWriteKey
        withUnsafeMutableBytes(of: &input.bytes) { destination in
            destination.copyBytes(from: bytes)
        }
        let (result, output) = invoke(&input)
        guard result == kIOReturnSuccess else { throw WriteError.transport(result) }
        guard output.result == 0 else { throw WriteError.controller(output.result) }
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
        let (result, output) = invoke(&input)
        return result == kIOReturnSuccess ? output : nil
    }

    private func invoke(_ input: inout SMCParamStruct) -> (kern_return_t, SMCParamStruct) {
        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride
        let kr = IOConnectCallStructMethod(connection, Self.handleYPCEvent,
                                           &input, MemoryLayout<SMCParamStruct>.stride,
                                           &output, &outSize)
        return (kr, output)
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
