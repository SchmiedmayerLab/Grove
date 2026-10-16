//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation
public import ModelsR4


/// A repository-assigned logical Resource id.
///
/// Source identities and UUID URNs belong in business identifiers and Bundle fullUrls;
/// this type exists only for callers that already have a repository id assignment.
public struct RepositoryID: Hashable, Sendable {
    // Spelled out rather than matched with `Regex`, which needs iOS 16/macOS 13 and would lift
    // this module above the package deployment floor.
    private static let allowedCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")

    public let rawValue: String

    public var primitive: FHIRPrimitive<FHIRString> {
        rawValue.asFHIRStringPrimitive()
    }

    public init(_ rawValue: String) throws(ExchangeIdentityError) {
        guard Self.isValidFHIRID(rawValue) else {
            throw .invalidRepositoryID(rawValue)
        }
        self.rawValue = rawValue
    }

    static func isValidFHIRID(_ value: String) -> Bool {
        (1...64).contains(value.count) && value.allSatisfy(allowedCharacters.contains)
    }
}


/// Errors raised before an invalid exchange graph can be serialized.
public enum ExchangeIdentityError: Error, Equatable, Sendable {
    case missingIdentifierSystem
    case missingIdentifierValue
    case invalidIdentifierSystem(String)
    case nonCanonicalIdentifierSystem(supplied: String, encoded: String)
    case invalidRepositoryID(String)
    case invalidKeyID(String)
    case invalidIdentifierRole(String)
    case duplicateIdentifierRole
    case identifierSystemRoleMismatch(
        system: String,
        first: GroveIdentifierRole,
        conflicting: GroveIdentifierRole
    )
    case invalidProducerInstance(UUID)
    case invalidEventIdentifier(String)
    case invalidEventSequence(String)
    case duplicateEntryIdentifier(BusinessIdentifier)
    case duplicateFullURL(String)
    case duplicateEntryKeyExtension
    case invalidEntryKeyRole
    case entryKeyPriorityMismatch
    case invalidEntryNodeRole
    case invalidEntryNodeValue(String)
    case missingFullURL
    case missingResource
    case unresolvedInternalReference(String)
    case containedResourcesProhibited
    case incorrectInternalReferenceType(reference: String, declared: String, actual: String)
    case incorrectFullURL(actual: String, expected: String)
    case invalidNamespace(String)
    case identityComponentTooLarge(Int)
    case identityFramingFailure
    case invalidInstant

    /// The registered diagnostic, the same on every platform for the same fault.
    ///
    /// A stored event identifier out of its canonical form is the fault a record can carry; every other one is a
    /// producer or deployment defect.
    public var diagnostic: ProducerDiagnostic {
        if case .invalidEventIdentifier = self {
            ExchangeGraphRule.mobileExchangeEventIdentity.diagnostic
        } else {
            ExchangeGraphRule.mobileInputUnclassified.diagnostic
        }
    }
}


/// The normative Grove Mobile exchange-entry identity checks a graph runs before it is accepted.
package enum ExchangeIdentity {
    /// Verifies that one Grove Identifier namespace has one graph role throughout a Bundle.
    ///
    /// The check walks nested identifier-only References and Provenance entities as well as
    /// top-level resource and entry identifiers. Untyped and non-Grove identifiers remain open.
    static func validateIdentifierSystemRoles(in bundle: ModelsR4.Bundle) throws {
        let data = try JSONEncoder().encode(bundle)
        let json = try JSONSerialization.jsonObject(with: data)
        var roleBySystem: [String: GroveIdentifierRole] = [:]
        try walkJSONObjects(json) { object in
            guard let type = object["type"] as? [String: Any],
                  let codings = type["coding"] as? [[String: Any]] else {
                return
            }
            let groveRoleCodings = codings.filter {
                $0["system"] as? String == Canonicals.identifierRoleCodeSystemValue
            }
            guard !groveRoleCodings.isEmpty else {
                return
            }
            guard groveRoleCodings.count == 1,
                  let rawRole = groveRoleCodings[0]["code"] as? String,
                  let role = GroveIdentifierRole(rawValue: rawRole),
                  let system = object["system"] as? String else {
                throw ExchangeIdentityError.invalidIdentifierRole("missing")
            }
            _ = try IdentifierSystem(system)
            if let first = roleBySystem[system], first != role {
                throw ExchangeIdentityError.identifierSystemRoleMismatch(
                    system: system,
                    first: first,
                    conflicting: role
                )
            }
            roleBySystem[system] = role
        }
    }

    /// Visits every JSON object of a decoded resource tree, parents before children.
    static func walkJSONObjects<E: Error>(
        _ value: Any,
        visit: ([String: Any]) throws(E) -> Void
    ) throws(E) {
        if let object = value as? [String: Any] {
            try visit(object)
            for child in object.values {
                try walkJSONObjects(child, visit: visit)
            }
        } else if let array = value as? [Any] {
            for child in array {
                try walkJSONObjects(child, visit: visit)
            }
        }
    }

    /// Validates the exact, pre-decoding namespace text of every Grove-typed Identifier in JSON.
    ///
    /// `FHIRURI` is backed by `Foundation.URL`, which can percent-encode an IRI while decoding, so
    /// stored bytes are checked before model decoding can accept a noncanonical identity in
    /// normalized form.
    package static func validateSerializedIdentifierSystems(in data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data)
        try walkJSONObjects(json) { object in
            guard let type = object["type"] as? [String: Any],
                  let codings = type["coding"] as? [[String: Any]],
                  codings.contains(where: { $0["system"] as? String == Canonicals.identifierRoleCodeSystemValue }) else {
                return
            }
            guard let system = object["system"] as? String else {
                throw ExchangeIdentityError.missingIdentifierSystem
            }
            _ = try IdentifierSystem(system)
        }
    }

    /// Whether a value has the canonical wire form of a Grove opaque identity.
    package static func isCanonicalOpaqueIdentifierValue(_ value: String) -> Bool {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 4,
              components[0] == "v0",
              OpaqueIdentityScope.isValidKeyID(String(components[1])),
              (try? EventSequence(String(components[2]))) != nil,
              components[3].utf8.count == 43,
              components[3].utf8.allSatisfy({
                  $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x5F
              }) else {
            return false
        }
        return true
    }
}


extension ExchangeIdentity {
    /// Returns the identifiers whose `Identifier.type` carries a Grove identifier role.
    ///
    /// A malformed Grove-typed identifier fails closed. Untyped business identifiers are not part
    /// of the exchange identity graph and are intentionally omitted.
    static func typedResourceIdentifiers(
        in resource: ResourceProxy?
    ) throws -> [RoledIdentifier] {
        guard let resource else {
            return []
        }
        let data = try JSONEncoder().encode(resource)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawIdentifiers = object["identifier"] as? [[String: Any]] else {
            return []
        }
        var identifiers: [RoledIdentifier] = []
        for rawIdentifier in rawIdentifiers {
            let data = try JSONSerialization.data(withJSONObject: rawIdentifier)
            let identifier = try JSONDecoder().decode(Identifier.self, from: data)
            let carriesGroveRole = identifier.type?.coding?.contains {
                $0.system?.value?.url.absoluteString == Canonicals.identifierRoleCodeSystemValue
            } == true
            guard carriesGroveRole else {
                continue
            }
            identifiers.append(try RoledIdentifier(identifier))
        }
        return identifiers
    }
}
