//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Source evidence naming the application that wrote a record, independently of the converting application.
/// Identifier systems must describe the upstream key space; no application release or host is inferred.
public struct SourceApplicationDevice: Sendable {
    /// Invalid or ambiguous source application evidence.
    public enum ValidationError: Error, Equatable, Sendable {
        case missingIdentifier
        case duplicateIdentifier
        case blankFact
    }

    public let identifiers: [BusinessIdentifier]
    public let name: String?
    public let version: String?
    public let build: String?

    public init(identifiers: [BusinessIdentifier], name: String? = nil, version: String? = nil, build: String? = nil) throws(ValidationError) {
        guard !identifiers.isEmpty else { throw .missingIdentifier }
        let pairs = identifiers.map { [Array($0.system.rawValue.utf8), Array($0.value.utf8)] }
        guard Set(pairs).count == identifiers.count else { throw .duplicateIdentifier }
        guard [name, version, build].allSatisfy({ $0?.isBlank != true }) else { throw .blankFact }
        self.identifiers = identifiers.sorted {
            if !$0.system.rawValue.utf8.elementsEqual($1.system.rawValue.utf8) {
                return $0.system.rawValue.utf8.lexicographicallyPrecedes($1.system.rawValue.utf8)
            }
            return $0.value.utf8.lexicographicallyPrecedes($1.value.utf8)
        }
        self.name = name
        self.version = version
        self.build = build
    }
}
