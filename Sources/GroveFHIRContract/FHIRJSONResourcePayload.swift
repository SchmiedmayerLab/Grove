//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// The package facade and its deliberately small recursive scanner stay together so adapters cannot
// accidentally select a less strict parser.
// swiftlint:disable file_types_order type_contents_order

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
        guard !data.starts(with: [0xEF, 0xBB, 0xBF]),
              let source = String(data: data, encoding: .utf8) else {
            throw .invalidJSON
        }
        do {
            var scanner = StrictJSONScanner(source)
            try scanner.validate()
            let envelope = try JSONDecoder().decode(ResourceEnvelope.self, from: data)
            guard Self.isFHIRResourceType(envelope.resourceType) else {
                throw ValidationError.invalidResourceType
            }
        } catch let error as ValidationError {
            throw error
        } catch {
            throw .invalidJSON
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


private struct StrictJSONScanner {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
    }

    mutating func validate() throws(FHIRJSONResourcePayload.ValidationError) {
        skipWhitespace()
        try parseValue()
        skipWhitespace()
        guard isAtEnd else {
            throw .invalidJSON
        }
    }

    private mutating func parseValue() throws(FHIRJSONResourcePayload.ValidationError) {
        guard let scalar = current else {
            throw .invalidJSON
        }
        switch scalar {
        case "{": try parseObject()
        case "[": try parseArray()
        case "\"": _ = try parseString()
        default: try parsePrimitive()
        }
    }

    private mutating func parseObject() throws(FHIRJSONResourcePayload.ValidationError) {
        advance()
        skipWhitespace()
        if consume("}") {
            return
        }
        var keys: Set<String> = []
        while true {
            guard current == "\"" else {
                throw .invalidJSON
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw .duplicateObjectKey(key)
            }
            skipWhitespace()
            guard consume(":") else {
                throw .invalidJSON
            }
            skipWhitespace()
            try parseValue()
            skipWhitespace()
            if consume("}") {
                return
            }
            guard consume(",") else {
                throw .invalidJSON
            }
            skipWhitespace()
        }
    }

    private mutating func parseArray() throws(FHIRJSONResourcePayload.ValidationError) {
        advance()
        skipWhitespace()
        if consume("]") {
            return
        }
        while true {
            try parseValue()
            skipWhitespace()
            if consume("]") {
                return
            }
            guard consume(",") else {
                throw .invalidJSON
            }
            skipWhitespace()
        }
    }

    private mutating func parseString() throws(FHIRJSONResourcePayload.ValidationError) -> String {
        let start = index
        guard consume("\"") else {
            throw .invalidJSON
        }
        while let scalar = current {
            if scalar == "\"" {
                advance()
                let literal = String(String.UnicodeScalarView(scalars[start..<index]))
                guard let data = literal.data(using: .utf8),
                      let value = try? JSONDecoder().decode(String.self, from: data) else {
                    throw .invalidJSON
                }
                return value
            }
            if scalar == "\\" {
                advance()
                guard current != nil else {
                    throw .invalidJSON
                }
                advance()
                continue
            }
            guard scalar.value >= 0x20 else {
                throw .invalidJSON
            }
            advance()
        }
        throw .invalidJSON
    }

    private mutating func parsePrimitive() throws(FHIRJSONResourcePayload.ValidationError) {
        let start = index
        while let scalar = current,
              !Self.isValueDelimiter(scalar) {
            advance()
        }
        guard index > start else {
            throw .invalidJSON
        }
    }

    private static func isValueDelimiter(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "," || scalar == "]" || scalar == "}" || isWhitespace(scalar)
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
    }

    private mutating func skipWhitespace() {
        while let scalar = current, Self.isWhitespace(scalar) {
            advance()
        }
    }

    @discardableResult
    private mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
        guard current == scalar else {
            return false
        }
        advance()
        return true
    }

    private var current: Unicode.Scalar? {
        isAtEnd ? nil : scalars[index]
    }

    private var isAtEnd: Bool {
        index == scalars.count
    }

    private mutating func advance() {
        index += 1
    }
}
