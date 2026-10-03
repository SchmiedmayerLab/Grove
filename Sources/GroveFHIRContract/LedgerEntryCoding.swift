//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation


/// The keys of the ledger's entries: `producer`, `event/<event key>` and `facts/<digest>`, all ASCII from
/// `[A-Za-z0-9_/-]` and at most 64 bytes.
enum LedgerKey {
    static let producer = "producer"
    static let eventPrefix = "event/"
    static let factsPrefix = "facts/"

    static func event(_ key: ExchangeEventKey) -> String {
        eventPrefix + key.rawValue
    }

    static func facts(_ digest: String) -> String {
        factsPrefix + digest
    }
}


/// How every ledger value is written and read: JSON with sorted members and unescaped slashes, carrying its
/// layout version under `"v"`. A later version is refused, anything malformed is corrupt; nothing traps.
enum LedgerEntryCoding {
    private struct Header: Decodable {
        enum CodingKeys: String, CodingKey {
            case version = "v"
        }

        let version: Int?
    }

    static let version = 1

    static func encode(_ payload: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    static func decode<Payload: Decodable>(_ type: Payload.Type, from value: Data, key: String) throws -> Payload {
        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: value)
        } catch {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: key)
        }
        guard let version = header.version else {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: key)
        }
        guard version <= Self.version else {
            throw ExchangeEventSequencer.LedgerError.unsupportedEntryVersion(key: key, version: version)
        }
        guard version == Self.version else {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: key)
        }
        do {
            return try JSONDecoder().decode(type, from: value)
        } catch {
            throw ExchangeEventSequencer.LedgerError.corruptEntry(key: key)
        }
    }

    /// A canonical positive decimal within `UInt64`, such as a sequence or the next one.
    static func positiveInteger(_ text: String) -> UInt64? {
        guard CanonicalNonnegativeDecimal.isCanonical(text), text != "0" else {
            return nil
        }
        return UInt64(text)
    }

    /// A producer instance: a UUID stating an RFC 4122 version and variant, as every event identifier requires.
    static func instance(_ text: String) -> UUID? {
        guard let uuid = UUID(uuidString: text), ExchangeEventIdentifier.statesRFC4122Version(uuid.uuidString.lowercased()) else {
            return nil
        }
        return uuid
    }
}
