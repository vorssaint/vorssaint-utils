// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Google Authenticator's transfer format: `otpauth-migration://offline?data=`
/// carrying a base64 protobuf. Read and written by hand, since the message
/// has six fields and a dependency would outweigh it.
///
///     message MigrationPayload {
///       repeated OtpParameters otp_parameters = 1;
///       int32 version = 2;  int32 batch_size = 3;  int32 batch_index = 4;  int32 batch_id = 5;
///     }
///     message OtpParameters {
///       bytes secret = 1;  string name = 2;  string issuer = 3;
///       Algorithm algorithm = 4;  DigitCount digits = 5;  OtpType type = 6;  int64 counter = 7;
///     }
enum GoogleMigration {
    enum DecodeError: Error, Equatable {
        case notMigrationURI
        case malformedPayload
    }

    /// Google shows ten accounts per code, so exports match what a phone
    /// expects to scan.
    static let batchSize = 10

    // MARK: - Decode

    static func decode(uri: String) throws -> [OTPEntry] {
        guard let components = URLComponents(string: uri.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "otpauth-migration",
              let encoded = components.queryItems?.first(where: { $0.name == "data" })?.value
        else { throw DecodeError.notMigrationURI }
        // The query value comes back percent-decoded; "+" inside base64 may
        // have been read as a space by a lax encoder.
        var base64 = encoded.replacingOccurrences(of: " ", with: "+")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { throw DecodeError.malformedPayload }
        return try decode(payload: data)
    }

    static func decode(payload: Data) throws -> [OTPEntry] {
        var reader = ProtobufReader(bytes: Array(payload))
        var entries: [OTPEntry] = []
        while let (field, wire) = try reader.readTag() {
            if field == 1, wire == .lengthDelimited {
                if let entry = try decodeParameters(reader.readBytes()) {
                    entries.append(entry)
                }
            } else {
                try reader.skip(wire)
            }
        }
        return entries
    }

    /// Nil for an entry the app cannot compute (MD5, unknown type), which the
    /// caller counts and reports rather than importing something wrong.
    private static func decodeParameters(_ bytes: [UInt8]) throws -> OTPEntry? {
        var reader = ProtobufReader(bytes: bytes)
        var account = OTPAccount()
        var secret = Data()
        var supported = true
        while let (field, wire) = try reader.readTag() {
            switch (field, wire) {
            case (1, .lengthDelimited): secret = Data(try reader.readBytes())
            case (2, .lengthDelimited): account.label = String(decoding: try reader.readBytes(), as: UTF8.self)
            case (3, .lengthDelimited): account.issuer = String(decoding: try reader.readBytes(), as: UTF8.self)
            case (4, .varint):
                switch try reader.readVarint() {
                case 0, 1: account.algorithm = .sha1
                case 2: account.algorithm = .sha256
                case 3: account.algorithm = .sha512
                default: supported = false
                }
            case (5, .varint):
                switch try reader.readVarint() {
                case 0, 1: account.digits = 6
                case 2: account.digits = 8
                default: supported = false
                }
            case (6, .varint):
                switch try reader.readVarint() {
                case 1: account.kind = .hotp
                case 0, 2: account.kind = .totp
                default: supported = false
                }
            case (7, .varint): account.counter = try reader.readVarint()
            default: try reader.skip(wire)
            }
        }
        guard supported, !secret.isEmpty else { return nil }
        // Google writes "issuer:name" into the name when the QR had both,
        // with or without the issuer field beside it.
        if let colon = account.label.firstIndex(of: ":") {
            let prefix = String(account.label[..<colon]).trimmingCharacters(in: .whitespaces)
            if account.issuer.isEmpty || account.issuer.caseInsensitiveCompare(prefix) == .orderedSame {
                account.issuer = prefix
                account.label = String(account.label[account.label.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        if account.issuer.caseInsensitiveCompare("Steam") == .orderedSame, account.kind == .totp {
            account.kind = .steam
            account.digits = OTPAccount.steamDigits
        }
        return OTPEntry(account: account, secret: secret)
    }

    // MARK: - Encode

    /// One URI per batch of ten, numbered so a phone can tell them apart.
    static func uris(for entries: [OTPEntry]) -> [String] {
        guard !entries.isEmpty else { return [] }
        let batches = stride(from: 0, to: entries.count, by: batchSize).map {
            Array(entries[$0..<min($0 + batchSize, entries.count)])
        }
        let batchID = Int(Date().timeIntervalSince1970) & 0x7fff_ffff
        return batches.enumerated().map { index, batch in
            let payload = encode(batch, batchSize: batches.count, batchIndex: index, batchID: batchID)
            let base64 = payload.base64EncodedString()
            // "+" and "/" must be escaped or the phone reads them as query syntax.
            let query = base64.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? base64
            return "otpauth-migration://offline?data=" + query
        }
    }

    static func encode(_ entries: [OTPEntry], batchSize: Int = 1, batchIndex: Int = 0, batchID: Int = 0) -> Data {
        var writer = ProtobufWriter()
        for entry in entries {
            writer.writeBytes(field: 1, encodeParameters(entry))
        }
        writer.writeVarint(field: 2, 1)
        writer.writeVarint(field: 3, UInt64(batchSize))
        writer.writeVarint(field: 4, UInt64(batchIndex))
        writer.writeVarint(field: 5, UInt64(batchID))
        return Data(writer.bytes)
    }

    private static func encodeParameters(_ entry: OTPEntry) -> [UInt8] {
        let account = entry.account
        var writer = ProtobufWriter()
        writer.writeBytes(field: 1, Array(entry.secret))
        writer.writeBytes(field: 2, Array(account.label.utf8))
        if !account.issuer.isEmpty {
            writer.writeBytes(field: 3, Array(account.issuer.utf8))
        }
        let algorithm: UInt64
        switch account.kind == .steam ? .sha1 : account.algorithm {
        case .sha1: algorithm = 1
        case .sha256: algorithm = 2
        case .sha512: algorithm = 3
        }
        writer.writeVarint(field: 4, algorithm)
        writer.writeVarint(field: 5, account.digits == 8 ? 2 : 1)
        writer.writeVarint(field: 6, account.kind == .hotp ? 1 : 2)
        if account.kind == .hotp {
            writer.writeVarint(field: 7, account.counter)
        }
        return writer.bytes
    }

    // MARK: - Wire format

    enum WireType: UInt8 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    struct ProtobufReader {
        private let bytes: [UInt8]
        private var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func readTag() throws -> (field: UInt64, wire: WireType)? {
            guard index < bytes.count else { return nil }
            let tag = try readVarint()
            guard let wire = WireType(rawValue: UInt8(tag & 0x07)) else {
                throw DecodeError.malformedPayload
            }
            return (tag >> 3, wire)
        }

        mutating func readVarint() throws -> UInt64 {
            var value: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                guard index < bytes.count, shift < 64 else { throw DecodeError.malformedPayload }
                let byte = bytes[index]
                index += 1
                value |= UInt64(byte & 0x7f) << shift
                if byte & 0x80 == 0 { return value }
                shift += 7
            }
        }

        mutating func readBytes() throws -> [UInt8] {
            let length = Int(try readVarint())
            guard length >= 0, index + length <= bytes.count else { throw DecodeError.malformedPayload }
            let slice = Array(bytes[index..<index + length])
            index += length
            return slice
        }

        mutating func skip(_ wire: WireType) throws {
            switch wire {
            case .varint: _ = try readVarint()
            case .fixed64: try advance(8)
            case .lengthDelimited: _ = try readBytes()
            case .fixed32: try advance(4)
            }
        }

        private mutating func advance(_ count: Int) throws {
            guard index + count <= bytes.count else { throw DecodeError.malformedPayload }
            index += count
        }
    }

    struct ProtobufWriter {
        private(set) var bytes: [UInt8] = []

        mutating func writeVarint(field: UInt64, _ value: UInt64) {
            appendVarint(field << 3 | UInt64(WireType.varint.rawValue))
            appendVarint(value)
        }

        mutating func writeBytes(field: UInt64, _ value: [UInt8]) {
            appendVarint(field << 3 | UInt64(WireType.lengthDelimited.rawValue))
            appendVarint(UInt64(value.count))
            bytes.append(contentsOf: value)
        }

        private mutating func appendVarint(_ value: UInt64) {
            var value = value
            repeat {
                var byte = UInt8(value & 0x7f)
                value >>= 7
                if value != 0 { byte |= 0x80 }
                bytes.append(byte)
            } while value != 0
        }
    }
}
