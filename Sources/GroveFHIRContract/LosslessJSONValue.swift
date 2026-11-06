//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


/// The exact value of a JSON number lexeme: its sign, its significant digits and the power of ten that scales them, so
/// `72`, `72.0` and `7.2e1` are one value and nothing is rounded.
private struct ExactNumber: Equatable {
    let isNegative: Bool
    let digits: Substring
    let exponent: Int64

    /// The value of a lexeme the parser admitted; `nil` for an exponent of 2^32 or more in magnitude, which then
    /// compares by its lexeme alone.
    init?(_ lexeme: String) {
        let parts = lexeme.split(maxSplits: 1) { $0 == "e" || $0 == "E" }
        guard let mantissa = parts.first, let stated = parts.count == 2 ? Int64(parts[1]) : 0, stated.magnitude < 1 << 32 else {
            return nil
        }
        let point = mantissa.firstIndex(of: ".")
        let fraction = point.map { mantissa[mantissa.index(after: $0)...] } ?? ""
        let significant = (mantissa[..<(point ?? mantissa.endIndex)].drop { $0 == "-" } + fraction).drop { $0 == "0" }
        let trailingZeros = significant.reversed().prefix { $0 == "0" }.count
        self.digits = significant.dropLast(trailingZeros)
        // Zero has neither sign nor scale, whatever its lexeme.
        self.isNegative = !digits.isEmpty && mantissa.hasPrefix("-")
        self.exponent = digits.isEmpty ? 0 : stated - Int64(fraction.count) + Int64(trailingZeros)
    }
}


/// A JSON document read without losing what the receiver compares: number lexemes stay text, and strings
/// keep every Unicode scalar they were written with.
///
/// Equality is the exchange protocol's token equality (`exchange-protocol.json` `semanticComparison`), which the
/// guide's reference comparator decides over code points: strings compare scalar by scalar, so canonically equivalent
/// spellings such as `U+00E9` and `e U+0301` are different content, and nothing is normalized. The parser refuses a
/// member name with a scalar above U+007F, as `grove-canonical-json-v0` does, so `String` keys compare bytewise and it
/// refuses exactly the duplicates the guide's reference parser refuses.
package indirect enum LosslessJSONValue: Equatable, Sendable {
    case object([String: LosslessJSONValue])
    case array([LosslessJSONValue])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null

    /// Why a text has no lossless reading, by its `grove-canonical-json-v0` refusal code.
    package enum ParseError: String, Error, Sendable {
        case invalidJSON = "invalid-json"
        case invalidUTF8 = "invalid-utf8"
        case byteOrderMark = "byte-order-mark"
        case duplicateMember = "duplicate-member"
        case nonASCIIMemberName = "non-ascii-member-name"
        case unpairedSurrogate = "unpaired-surrogate"
    }

    private struct Parser {
        private static let simpleEscapes: [UInt8: Unicode.Scalar] = [
            UInt8(ascii: "\""): "\"", UInt8(ascii: "\\"): "\\", UInt8(ascii: "/"): "/", UInt8(ascii: "b"): "\u{08}",
            UInt8(ascii: "f"): "\u{0C}", UInt8(ascii: "n"): "\n", UInt8(ascii: "r"): "\r", UInt8(ascii: "t"): "\t"
        ]

        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index >= bytes.count }

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }

        mutating func value() throws(ParseError) -> LosslessJSONValue {
            skipWhitespace()
            guard index < bytes.count else {
                throw .invalidJSON
            }
            switch bytes[index] {
            case UInt8(ascii: "{"):
                return try object()
            case UInt8(ascii: "["):
                return try array()
            case UInt8(ascii: "\""):
                return .string(try string())
            case UInt8(ascii: "t"):
                try literal("true")
                return .boolean(true)
            case UInt8(ascii: "f"):
                try literal("false")
                return .boolean(false)
            case UInt8(ascii: "n"):
                try literal("null")
                return .null
            default:
                return .number(try number())
            }
        }

        private mutating func object() throws(ParseError) -> LosslessJSONValue {
            index += 1
            var members: [String: LosslessJSONValue] = [:]
            skipWhitespace()
            if try consume(UInt8(ascii: "}")) {
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                    throw .invalidJSON
                }
                let key = try string()
                guard key.utf8.allSatisfy({ $0 < 0x80 }) else {
                    throw .nonASCIIMemberName
                }
                skipWhitespace()
                guard try consume(UInt8(ascii: ":")) else {
                    throw .invalidJSON
                }
                guard members.updateValue(try value(), forKey: key) == nil else {
                    throw .duplicateMember
                }
                skipWhitespace()
                if try consume(UInt8(ascii: ",")) {
                    continue
                }
                guard try consume(UInt8(ascii: "}")) else {
                    throw .invalidJSON
                }
                return .object(members)
            }
        }

        private mutating func array() throws(ParseError) -> LosslessJSONValue {
            index += 1
            var elements: [LosslessJSONValue] = []
            skipWhitespace()
            if try consume(UInt8(ascii: "]")) {
                return .array(elements)
            }
            while true {
                elements.append(try value())
                skipWhitespace()
                if try consume(UInt8(ascii: ",")) {
                    continue
                }
                guard try consume(UInt8(ascii: "]")) else {
                    throw .invalidJSON
                }
                return .array(elements)
            }
        }

        private mutating func consume(_ byte: UInt8) throws(ParseError) -> Bool {
            guard index < bytes.count else {
                throw .invalidJSON
            }
            guard bytes[index] == byte else {
                return false
            }
            index += 1
            return true
        }

        private mutating func literal(_ text: String) throws(ParseError) {
            let expected = Array(text.utf8)
            guard bytes.count - index >= expected.count,
                  Array(bytes[index..<(index + expected.count)]) == expected else {
                throw .invalidJSON
            }
            index += expected.count
        }

        private mutating func number() throws(ParseError) -> String {
            let start = index
            if try consume(UInt8(ascii: "-")) {}
            try digits(allowingLeadingZeroOnly: true)
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                try digits(allowingLeadingZeroOnly: false)
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                    index += 1
                }
                try digits(allowingLeadingZeroOnly: false)
            }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }

        private mutating func digits(allowingLeadingZeroOnly: Bool) throws(ParseError) {
            let start = index
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                index += 1
            }
            guard index > start else {
                throw .invalidJSON
            }
            if allowingLeadingZeroOnly, bytes[start] == 0x30, index - start > 1 {
                throw .invalidJSON
            }
        }

        private mutating func string() throws(ParseError) -> String {
            index += 1
            var scalars = String.UnicodeScalarView()
            var utf8Run: [UInt8] = []
            // Decoded scalar by scalar: `String(bytes:encoding:)` would drop a leading U+FEFF as a byte order mark.
            func flushRun() throws(ParseError) {
                var decoder = UTF8()
                var iterator = utf8Run.makeIterator()
                while true {
                    switch decoder.decode(&iterator) {
                    case .scalarValue(let scalar):
                        scalars.append(scalar)
                    case .emptyInput:
                        utf8Run.removeAll()
                        return
                    case .error:
                        throw .invalidUTF8
                    }
                }
            }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "\""):
                    try flushRun()
                    return String(scalars)
                case UInt8(ascii: "\\"):
                    try flushRun()
                    scalars.append(try escape())
                case 0x00...0x1F:
                    throw .invalidJSON
                default:
                    utf8Run.append(byte)
                }
            }
            throw .invalidJSON
        }

        private mutating func escape() throws(ParseError) -> Unicode.Scalar {
            guard index < bytes.count else {
                throw .invalidJSON
            }
            let byte = bytes[index]
            index += 1
            if let scalar = Self.simpleEscapes[byte] {
                return scalar
            }
            guard byte == UInt8(ascii: "u") else {
                throw .invalidJSON
            }
            return try unicodeEscape()
        }

        private mutating func unicodeEscape() throws(ParseError) -> Unicode.Scalar {
            let unit = try codeUnit()
            guard UTF16.isLeadSurrogate(unit) else {
                guard !UTF16.isTrailSurrogate(unit), let scalar = Unicode.Scalar(unit) else {
                    throw .unpairedSurrogate
                }
                return scalar
            }
            guard try consume(UInt8(ascii: "\\")), try consume(UInt8(ascii: "u")) else {
                throw .unpairedSurrogate
            }
            let trail = try codeUnit()
            guard UTF16.isTrailSurrogate(trail),
                  let scalar = UTF16.decode(UTF16.EncodedScalar([unit, trail])) as Unicode.Scalar? else {
                throw .unpairedSurrogate
            }
            return scalar
        }

        private mutating func codeUnit() throws(ParseError) -> UInt16 {
            guard bytes.count - index >= 4,
                  bytes[index..<(index + 4)].allSatisfy(\.isASCIIHexDigit),
                  let unit = UInt16(String(decoding: bytes[index..<(index + 4)], as: UTF8.self), radix: 16) else {
                throw .invalidJSON
            }
            index += 4
            return unit
        }
    }

    package init(parsing data: Data) throws(ParseError) {
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]) else {
            throw .byteOrderMark
        }
        var parser = Parser(bytes: Array(data))
        let value = try parser.value()
        parser.skipWhitespace()
        guard parser.isAtEnd else {
            throw .invalidJSON
        }
        self = value
    }
}


extension LosslessJSONValue {
    /// Token equality, with strings and lexemes compared scalar by scalar.
    package static func == (lhs: LosslessJSONValue, rhs: LosslessJSONValue) -> Bool {
        lhs.matches(rhs) { $0.unicodeScalars.elementsEqual($1.unicodeScalars) }
    }

    /// Whether `kept`, the FHIR model's encoding of what it decoded from this document, states the same content: the
    /// same members, elements and scalars, with numbers compared by their exact value, as the model rewrites a decimal
    /// lexeme such as `72.0` but must not round a value or rewrite any other scalar.
    func isKept(as kept: LosslessJSONValue) -> Bool {
        matches(kept) { given, kept in
            given == kept || ExactNumber(given).map { $0 == ExactNumber(kept) } ?? false
        }
    }

    /// Token equality with numbers compared by `sameNumber`.
    private func matches(_ other: LosslessJSONValue, numbers sameNumber: (String, String) -> Bool) -> Bool {
        switch (self, other) {
        case let (.object(lhs), .object(rhs)):
            lhs.count == rhs.count && lhs.allSatisfy { name, value in
                rhs[name].map { value.matches($0, numbers: sameNumber) } ?? false
            }
        case let (.array(lhs), .array(rhs)):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.matches($1, numbers: sameNumber) }
        case let (.string(lhs), .string(rhs)):
            lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
        case let (.number(lhs), .number(rhs)):
            sameNumber(lhs, rhs)
        case let (.boolean(lhs), .boolean(rhs)):
            lhs == rhs
        case (.null, .null):
            true
        default:
            false
        }
    }
}
