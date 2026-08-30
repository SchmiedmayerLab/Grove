//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The parser mirrors JSON's grammar branch-for-branch and is intentionally kept in reading order.
// swiftlint:disable cyclomatic_complexity type_contents_order

import Foundation


enum StrictJSONEnvelopeError: Error, Equatable {
    case invalidJSON
    case byteOrderMark
    case scalarRoot
    case duplicateMember(String)
    case nonFiniteNumber
    case nestingLimit
}


/// A deliberately small recognizer for the strict JSON envelope used by registered recordings.
/// Foundation's JSON APIs accept duplicate object members and retain only one value, so using a
/// decoded dictionary alone cannot validate byte-preserved native evidence.
struct StrictJSONEnvelopeValidator {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func validate() throws {
        guard !bytes.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw StrictJSONEnvelopeError.byteOrderMark
        }
        guard String(data: Data(bytes), encoding: .utf8) != nil else {
            throw StrictJSONEnvelopeError.invalidJSON
        }
        skipWhitespace()
        guard let first = current, first == 0x7B || first == 0x5B else {
            throw StrictJSONEnvelopeError.scalarRoot
        }
        try parseValue(depth: 0)
        skipWhitespace()
        guard offset == bytes.count else {
            throw StrictJSONEnvelopeError.invalidJSON
        }
    }

    private var current: UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    private mutating func parseValue(depth: Int) throws {
        guard depth <= 512 else {
            throw StrictJSONEnvelopeError.nestingLimit
        }
        skipWhitespace()
        guard let current else {
            throw StrictJSONEnvelopeError.invalidJSON
        }
        switch current {
        case 0x7B: try parseObject(depth: depth + 1)
        case 0x5B: try parseArray(depth: depth + 1)
        case 0x22: _ = try parseString()
        case 0x74: try consume("true")
        case 0x66: try consume("false")
        case 0x6E: try consume("null")
        case 0x2D, 0x30...0x39: try parseNumber()
        default: throw StrictJSONEnvelopeError.invalidJSON
        }
    }

    private mutating func parseObject(depth: Int) throws {
        offset += 1
        skipWhitespace()
        if current == 0x7D {
            offset += 1
            return
        }
        var members: Set<String> = []
        while true {
            skipWhitespace()
            let member = try parseString()
            guard members.insert(member).inserted else {
                throw StrictJSONEnvelopeError.duplicateMember(member)
            }
            skipWhitespace()
            try consumeByte(0x3A)
            try parseValue(depth: depth)
            skipWhitespace()
            if current == 0x7D {
                offset += 1
                return
            }
            try consumeByte(0x2C)
        }
    }

    private mutating func parseArray(depth: Int) throws {
        offset += 1
        skipWhitespace()
        if current == 0x5D {
            offset += 1
            return
        }
        while true {
            try parseValue(depth: depth)
            skipWhitespace()
            if current == 0x5D {
                offset += 1
                return
            }
            try consumeByte(0x2C)
        }
    }

    private mutating func parseString() throws -> String {
        let start = offset
        try consumeByte(0x22)
        while let byte = current {
            switch byte {
            case 0x00...0x1F:
                throw StrictJSONEnvelopeError.invalidJSON
            case 0x22:
                offset += 1
                let encoded = Data(bytes[start..<offset])
                guard let decoded = try? JSONDecoder().decode(String.self, from: encoded) else {
                    throw StrictJSONEnvelopeError.invalidJSON
                }
                return decoded
            case 0x5C:
                offset += 1
                guard let escaped = current else {
                    throw StrictJSONEnvelopeError.invalidJSON
                }
                if escaped == 0x75 {
                    offset += 1
                    for _ in 0..<4 {
                        guard let scalar = current,
                              (0x30...0x39).contains(scalar)
                                || (0x41...0x46).contains(scalar)
                                || (0x61...0x66).contains(scalar) else {
                            throw StrictJSONEnvelopeError.invalidJSON
                        }
                        offset += 1
                    }
                } else {
                    guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escaped) else {
                        throw StrictJSONEnvelopeError.invalidJSON
                    }
                    offset += 1
                }
            default:
                offset += 1
            }
        }
        throw StrictJSONEnvelopeError.invalidJSON
    }

    private mutating func parseNumber() throws {
        let start = offset
        if current == 0x2D {
            offset += 1
        }
        guard let first = current else {
            throw StrictJSONEnvelopeError.invalidJSON
        }
        if first == 0x30 {
            offset += 1
            if let current, (0x30...0x39).contains(current) {
                throw StrictJSONEnvelopeError.invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw StrictJSONEnvelopeError.invalidJSON
            }
            repeat { offset += 1 } while current.map { (0x30...0x39).contains($0) } == true
        }
        if current == 0x2E {
            offset += 1
            try consumeDigits()
        }
        if current == 0x65 || current == 0x45 {
            offset += 1
            if current == 0x2B || current == 0x2D {
                offset += 1
            }
            try consumeDigits()
        }
        guard let value = Double(String(decoding: bytes[start..<offset], as: UTF8.self)), value.isFinite else {
            throw StrictJSONEnvelopeError.nonFiniteNumber
        }
    }

    private mutating func consumeDigits() throws {
        guard let current, (0x30...0x39).contains(current) else {
            throw StrictJSONEnvelopeError.invalidJSON
        }
        repeat { offset += 1 } while self.current.map { (0x30...0x39).contains($0) } == true
    }

    private mutating func consume(_ text: StaticString) throws {
        for byte in String(describing: text).utf8 {
            try consumeByte(byte)
        }
    }

    private mutating func consumeByte(_ byte: UInt8) throws {
        guard current == byte else {
            throw StrictJSONEnvelopeError.invalidJSON
        }
        offset += 1
    }

    private mutating func skipWhitespace() {
        while let current, [0x20, 0x09, 0x0A, 0x0D].contains(current) {
            offset += 1
        }
    }
}
