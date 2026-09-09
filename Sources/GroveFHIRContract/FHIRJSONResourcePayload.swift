//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The package facade and the one strict scanner it shares stay together so adapters cannot
// accidentally select a less strict parser.
// swiftlint:disable file_types_order

package import Foundation


/// Package-local validation shared by adapters that carry release-neutral FHIR JSON bytes.
package enum FHIRJSONResourcePayload {
    package enum ValidationError: Error, Equatable, Sendable {
        case invalidJSON
        case duplicateObjectKey(String)
        case invalidResourceType
    }

    /// Validates the syntax Grove can prove without interpreting or rewriting an issuer's resource.
    package static func validate(_ data: Data) throws(ValidationError) {
        do {
            var scanner = StrictJSONScanner(data)
            try scanner.validate()
        } catch .duplicateMember(let name) {
            throw .duplicateObjectKey(name)
        } catch {
            throw .invalidJSON
        }
        guard let envelope = try? JSONDecoder().decode(ResourceEnvelope.self, from: data),
              Self.isFHIRResourceType(envelope.resourceType) else {
            throw .invalidResourceType
        }
    }

    private static func isFHIRResourceType(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first,
              (65...90).contains(first.value) else {
            return false
        }
        return scalars.dropFirst().allSatisfy {
            (65...90).contains($0.value)
                || (97...122).contains($0.value)
                || (48...57).contains($0.value)
        }
    }
}


private struct ResourceEnvelope: Decodable {
    let resourceType: String
}


/// The one strict JSON recognizer Grove producers validate byte-preserved payloads with.
///
/// Foundation's JSON APIs accept duplicate object members and retain only one value, so a decoded
/// dictionary alone cannot validate byte-preserved native evidence. The walk is over bytes and
/// depth-capped, so a deeply nested payload refuses instead of overflowing the stack.
package struct StrictJSONScanner {
    package enum ScanError: Error, Equatable, Sendable {
        case invalidJSON
        case byteOrderMark
        case scalarRoot
        case duplicateMember(String)
        case nonFiniteNumber
        case nestingLimit
    }

    private static let nestingLimit = 512

    private let bytes: [UInt8]
    private var offset = 0

    private var current: UInt8? {
        offset < bytes.count ? bytes[offset] : nil
    }

    package init(_ data: Data) {
        bytes = Array(data)
    }

    package mutating func validate() throws(ScanError) {
        guard !bytes.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw .byteOrderMark
        }
        guard String(data: Data(bytes), encoding: .utf8) != nil else {
            throw .invalidJSON
        }
        skipWhitespace()
        guard let first = current, first == 0x7B || first == 0x5B else {
            throw .scalarRoot
        }
        try parseValue(depth: 0)
        skipWhitespace()
        guard offset == bytes.count else {
            throw .invalidJSON
        }
    }

    private mutating func parseValue(depth: Int) throws(ScanError) {
        guard depth <= Self.nestingLimit else {
            throw .nestingLimit
        }
        skipWhitespace()
        guard let current else {
            throw .invalidJSON
        }
        switch current {
        case 0x7B: try parseObject(depth: depth + 1)
        case 0x5B: try parseArray(depth: depth + 1)
        case 0x22: _ = try parseString()
        case 0x74: try consume("true")
        case 0x66: try consume("false")
        case 0x6E: try consume("null")
        case 0x2D, 0x30...0x39: try parseNumber()
        default: throw .invalidJSON
        }
    }

    private mutating func parseObject(depth: Int) throws(ScanError) {
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
                throw .duplicateMember(member)
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

    private mutating func parseArray(depth: Int) throws(ScanError) {
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

    private mutating func parseString() throws(ScanError) -> String {
        let start = offset
        try consumeByte(0x22)
        while let byte = current {
            switch byte {
            case 0x00...0x1F:
                throw .invalidJSON
            case 0x22:
                offset += 1
                let encoded = Data(bytes[start..<offset])
                guard let decoded = try? JSONDecoder().decode(String.self, from: encoded) else {
                    throw .invalidJSON
                }
                return decoded
            case 0x5C:
                try parseEscape()
            default:
                offset += 1
            }
        }
        throw .invalidJSON
    }

    private mutating func parseEscape() throws(ScanError) {
        offset += 1
        guard let escaped = current else {
            throw .invalidJSON
        }
        guard escaped == 0x75 else {
            guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escaped) else {
                throw .invalidJSON
            }
            offset += 1
            return
        }
        offset += 1
        for _ in 0..<4 {
            guard let scalar = current,
                  (0x30...0x39).contains(scalar)
                    || (0x41...0x46).contains(scalar)
                    || (0x61...0x66).contains(scalar) else {
                throw .invalidJSON
            }
            offset += 1
        }
    }

    private mutating func parseNumber() throws(ScanError) {
        let start = offset
        if current == 0x2D {
            offset += 1
        }
        guard let first = current else {
            throw .invalidJSON
        }
        if first == 0x30 {
            offset += 1
            if let current, (0x30...0x39).contains(current) {
                throw .invalidJSON
            }
        } else {
            guard (0x31...0x39).contains(first) else {
                throw .invalidJSON
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
            throw .nonFiniteNumber
        }
    }

    private mutating func consumeDigits() throws(ScanError) {
        guard let current, (0x30...0x39).contains(current) else {
            throw .invalidJSON
        }
        repeat { offset += 1 } while self.current.map { (0x30...0x39).contains($0) } == true
    }

    private mutating func consume(_ text: StaticString) throws(ScanError) {
        for byte in String(describing: text).utf8 {
            try consumeByte(byte)
        }
    }

    private mutating func consumeByte(_ byte: UInt8) throws(ScanError) {
        guard current == byte else {
            throw .invalidJSON
        }
        offset += 1
    }

    private mutating func skipWhitespace() {
        while let current, [0x20, 0x09, 0x0A, 0x0D].contains(current) {
            offset += 1
        }
    }
}
