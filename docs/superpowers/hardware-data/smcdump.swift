// Standalone read-only SMC key enumerator. Reuses the public AppleSMC ABI
// documented in Vorssaint's SMCClient.swift. Reads only — never writes.
import Foundation
import IOKit

struct SMCVersion { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
struct SMCPLimitData { var version: UInt16 = 0, length: UInt16 = 0; var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0 }
struct SMCKeyInfoData { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
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
    var bytes: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

let handleYPCEvent: UInt32 = 2
let cmdReadKey: UInt8 = 5
let cmdKeyFromIndex: UInt8 = 8
let cmdKeyInfo: UInt8 = 9

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
func fourCCString(_ v: UInt32) -> String {
    let c = [UInt8((v>>24)&0xff),UInt8((v>>16)&0xff),UInt8((v>>8)&0xff),UInt8(v&0xff)]
    return String(bytes: c, encoding: .ascii) ?? "????"
}

var conn: io_connect_t = 0
let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
guard svc != 0, IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
    print("cannot open AppleSMC"); exit(1)
}

func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
    var output = SMCParamStruct()
    var outSize = MemoryLayout<SMCParamStruct>.stride
    let kr = IOConnectCallStructMethod(conn, handleYPCEvent, &input, MemoryLayout<SMCParamStruct>.stride, &output, &outSize)
    return kr == kIOReturnSuccess ? output : nil
}

func keyCount() -> Int {
    var input = SMCParamStruct()
    input.key = fourCC("#KEY"); input.keyInfo.dataSize = 4; input.data8 = cmdReadKey
    guard let out = call(&input), out.result == 0 else { return 0 }
    let b = withUnsafeBytes(of: out.bytes) { Array($0.prefix(4)) }
    return Int(UInt32(b[0])<<24 | UInt32(b[1])<<16 | UInt32(b[2])<<8 | UInt32(b[3]))
}

func decode(_ type: String, _ bytes: [UInt8]) -> Double? {
    switch type {
    case "flt " where bytes.count == 4: return Double(bytes.withUnsafeBytes { $0.load(as: Float32.self) })
    case "sp78" where bytes.count == 2: return Double(Int16(bitPattern: UInt16(bytes[0])<<8 | UInt16(bytes[1]))) / 256.0
    case "ioft" where bytes.count == 8: return Double(bytes.withUnsafeBytes { $0.load(as: UInt64.self) }) / 65536.0
    case "fpe2" where bytes.count == 2: return Double(UInt16(bytes[0])<<8 | UInt16(bytes[1])) / 4.0
    case "ui8 " where bytes.count == 1: return Double(bytes[0])
    case "ui16" where bytes.count == 2: return Double(UInt16(bytes[0])<<8 | UInt16(bytes[1]))
    case "ui32" where bytes.count == 4: return Double(UInt32(bytes[0])<<24 | UInt32(bytes[1])<<16 | UInt32(bytes[2])<<8 | UInt32(bytes[3]))
    case "si8 " where bytes.count == 1: return Double(Int8(bitPattern: bytes[0]))
    case "si16" where bytes.count == 2: return Double(Int16(bitPattern: UInt16(bytes[0])<<8 | UInt16(bytes[1])))
    default: return nil
    }
}

let n = keyCount()
FileHandle.standardError.write("total SMC keys: \(n)\n".data(using: .utf8)!)

// Only dump keys whose first char is interesting: F(fans) P(power) T(temp) V(volt) I(current) c(current alt)
let wanted: Set<Character> = ["F","P","T","V","I"]
var rows: [(String,String,Double?)] = []
for i in 0..<n {
    var probe = SMCParamStruct(); probe.data8 = cmdKeyFromIndex; probe.data32 = UInt32(i)
    guard let out = call(&probe), out.result == 0 else { continue }
    let name = fourCCString(out.key)
    guard let first = name.first, wanted.contains(first) else { continue }
    var infoIn = SMCParamStruct(); infoIn.key = out.key; infoIn.data8 = cmdKeyInfo
    guard let info = call(&infoIn), info.result == 0 else { continue }
    let type = fourCCString(info.keyInfo.dataType)
    let size = info.keyInfo.dataSize
    var rd = SMCParamStruct(); rd.key = out.key; rd.keyInfo.dataSize = size; rd.data8 = cmdReadKey
    var value: Double? = nil
    if let vout = call(&rd), vout.result == 0 {
        let bytes = withUnsafeBytes(of: vout.bytes) { Array($0.prefix(Int(size))) }
        value = decode(type, bytes)
    }
    rows.append((name, type, value))
}
rows.sort { $0.0 < $1.0 }
for (name, type, value) in rows {
    let v = value.map { String(format: "%.2f", $0) } ?? "-"
    print("\(name)\t\(type)\t\(v)")
}
IOServiceClose(conn)
