//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

package import Foundation


/// The normative Grove Mobile exchange-entry identity checks a graph runs before it is accepted.
package enum ExchangeIdentity {
    /// Verifies that one Grove Identifier namespace has one graph role throughout a Bundle.
    ///
    /// The check walks nested identifier-only References and Provenance entities as well as
    /// top-level resource and entry identifiers. Untyped and non-Grove identifiers remain open.
    ///
    /// - Parameter json: The parsed JSON of the whole Bundle.
    static func validateIdentifierSystemRoles(inBundleJSON json: Any) throws {
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
        // The native containers and strings `WireJSONEncoder` builds are told apart by their exact type, which is far
        // cheaper than a failed cast; anything else, `JSONSerialization`'s objects among them, is cast.
        let valueType = type(of: value)
        if valueType == String.self {
            return
        }
        if valueType == [String: Any].self {
            // swiftlint:disable:next force_cast
            let object = value as! [String: Any]
            try visit(object)
            for child in object.values {
                try walkJSONObjects(child, visit: visit)
            }
            return
        }
        if valueType == [Any].self {
            // swiftlint:disable:next force_cast
            for child in value as! [Any] {
                try walkJSONObjects(child, visit: visit)
            }
            return
        }
        if value is NSNumber || value is NSNull {
            return
        }
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
        try validateSerializedIdentifierSystems(inJSON: JSONSerialization.jsonObject(with: data))
    }

    /// ``validateSerializedIdentifierSystems(in:)`` over JSON already parsed from the stored bytes.
    static func validateSerializedIdentifierSystems(inJSON json: Any) throws {
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
              isUnpaddedBase64URLDigest(components[3]) else {
            return false
        }
        return true
    }

    /// Whether `text` has the form of a SHA-256 digest in base64url without padding: 43 characters of `[A-Za-z0-9_-]`.
    static func isUnpaddedBase64URLDigest(_ text: some StringProtocol) -> Bool {
        text.utf8.count == 43 && text.utf8.allSatisfy { $0.isASCIIAlphaNumeric || $0 == 0x2D || $0 == 0x5F }
    }
}
