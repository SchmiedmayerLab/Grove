//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
package import Foundation


extension LosslessJSONValue {
    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// Decided byte by byte: every byte of a multi-byte scalar is above 0x7F, so only ASCII is ever escaped.
    private static func appendCanonicalString(_ string: String, to output: inout [UInt8]) {
        output.append(UInt8(ascii: "\""))
        for byte in string.utf8 {
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"):
                output.append(contentsOf: [UInt8(ascii: "\\"), byte])
            case 0x08:
                output.append(contentsOf: "\\b".utf8)
            case 0x09:
                output.append(contentsOf: "\\t".utf8)
            case 0x0A:
                output.append(contentsOf: "\\n".utf8)
            case 0x0C:
                output.append(contentsOf: "\\f".utf8)
            case 0x0D:
                output.append(contentsOf: "\\r".utf8)
            case 0x00...0x1F:
                output.append(contentsOf: "\\u00".utf8)
                output.append(contentsOf: [hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]])
            default:
                output.append(byte)
            }
        }
        output.append(UInt8(ascii: "\""))
    }

    /// The document in `grove-canonical-json-v0`, the byte form every Grove digest hashes.
    ///
    /// Object members sort by the bytes of their names, there is no insignificant whitespace, and array order is kept.
    /// A string is its scalars in UTF-8, with only the quotation mark, the reverse solidus and U+0000 to U+001F escaped
    /// as RFC 8785 section 3.2.2.2 escapes them. A number is its lexeme, verbatim.
    package func canonicalBytes() -> Data {
        var output: [UInt8] = []
        appendCanonicalBytes(to: &output)
        return Data(output)
    }

    private func appendCanonicalBytes(to output: inout [UInt8]) {
        switch self {
        case .object(let members):
            output.append(UInt8(ascii: "{"))
            for (index, member) in members.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }).enumerated() {
                if index > 0 {
                    output.append(UInt8(ascii: ","))
                }
                Self.appendCanonicalString(member.key, to: &output)
                output.append(UInt8(ascii: ":"))
                member.value.appendCanonicalBytes(to: &output)
            }
            output.append(UInt8(ascii: "}"))
        case .array(let elements):
            output.append(UInt8(ascii: "["))
            for (index, element) in elements.enumerated() {
                if index > 0 {
                    output.append(UInt8(ascii: ","))
                }
                element.appendCanonicalBytes(to: &output)
            }
            output.append(UInt8(ascii: "]"))
        case .string(let string):
            Self.appendCanonicalString(string, to: &output)
        case .number(let lexeme):
            output.append(contentsOf: lexeme.utf8)
        case .boolean(let value):
            output.append(contentsOf: (value ? "true" : "false").utf8)
        case .null:
            output.append(contentsOf: "null".utf8)
        }
    }
}


extension LosslessJSONValue {
    /// The tokens `value` encodes to, which are the tokens it states inside an encoded Bundle.
    package init(encoding value: some Encodable) throws(ExchangeIdentityError) {
        do {
            self = try LosslessJSONValue(parsing: ExchangeGraph.wireEncoding(of: value).json)
        } catch {
            throw .invalidDigestContent(String(reflecting: type(of: error)))
        }
    }
}


extension LosslessJSONValue {
    /// The `content-digest` component of a shared node's content-snapshot key: SHA-256, base64url without padding, over
    /// the node's canonical bytes minus `id` and minus its own key.
    ///
    /// The key is the node's snapshot Identifier in `identifier`, which is dropped if it becomes empty; on a
    /// QuestionnaireResponse, whose one `identifier` holds the submission's, it is every `grove-context-snapshot`
    /// extension, and `extension` is dropped if it becomes empty. Nothing else is removed.
    package var contentDigest: String {
        get throws(ExchangeIdentityError) {
            let content = try removingMember("id")
            switch try resourceType {
            case "QuestionnaireResponse":
                return try content.removingExtensions(url: Canonicals.contextSnapshotValue).canonicalDigest
            case "Device":
                return try content.removingIdentifiers(role: .deviceSnapshot).canonicalDigest
            case "Patient", "ResearchStudy", "ResearchSubject", "PlanDefinition":
                return try content.removingIdentifiers(role: .contextSnapshot).canonicalDigest
            case let resourceType:
                throw .invalidDigestContent("\(resourceType) carries no content-snapshot key")
            }
        }
    }

    private var canonicalDigest: String {
        Data(SHA256.hash(data: canonicalBytes())).base64URLEncodedStringWithoutPadding
    }

    private var resourceType: String {
        get throws(ExchangeIdentityError) {
            guard case .object(let members) = self, case .string(let resourceType)? = members["resourceType"] else {
                throw .invalidDigestContent("A resource states no resourceType")
            }
            return resourceType
        }
    }

    /// The `record-content-digest` component of a record-version key: SHA-256, base64url without padding, over the
    /// length-framed `org.grovealliance.fhir.record-content.v0`, the Provenance's canonical bytes and each output's.
    ///
    /// The Provenance loses `id` and every `grove-record-version` extension, with `extension` dropped if it is left
    /// empty; each output loses `id`. Nothing else is removed. A shared node that the Provenance or an output references
    /// enters through its content-derived fullUrl; a ResearchSubject joined only by the study rule, and any node only it
    /// reaches, stays outside the record version. Parse every resource from the bytes the record carries, never from a
    /// FHIR model's re-encoding, which rewrites decimal lexemes.
    ///
    /// - Parameters:
    ///   - provenance: The record's conversion Provenance.
    ///   - outputs: The resources `Provenance.target` resolves to, in target order.
    package static func recordContentDigest(
        provenance: LosslessJSONValue,
        outputs: [LosslessJSONValue]
    ) throws(ExchangeIdentityError) -> String {
        guard try provenance.resourceType == "Provenance" else {
            throw .invalidDigestContent("The record content starts with a Provenance")
        }
        guard case .object(let members) = provenance, case .array(let targets)? = members["target"], !targets.isEmpty else {
            throw .invalidDigestContent("A conversion Provenance targets at least one output")
        }
        guard targets.count == outputs.count else {
            throw .invalidDigestContent("A record states exactly one output per Provenance.target")
        }
        var fields = [
            Data("org.grovealliance.fhir.record-content.v0".utf8),
            try provenance.removingMember("id").removingExtensions(url: Canonicals.recordVersionValue).canonicalBytes()
        ]
        for output in outputs {
            fields.append(try output.removingMember("id").canonicalBytes())
        }
        return Data(SHA256.hash(data: try Data(lengthFramed: fields))).base64URLEncodedStringWithoutPadding
    }

    private func removingMember(_ name: String) throws(ExchangeIdentityError) -> LosslessJSONValue {
        guard case .object(var members) = self else {
            throw .invalidDigestContent("A resource is a JSON object")
        }
        members.removeValue(forKey: name)
        return .object(members)
    }

    /// This object minus every element of `extension` whose `url` is `url`, and minus `extension` if it is left empty.
    private func removingExtensions(url: String) throws(ExchangeIdentityError) -> LosslessJSONValue {
        try removingElements(of: "extension") { element in
            guard case .object(let members) = element, case .string(let elementURL)? = members["url"] else {
                return false
            }
            return elementURL == url
        }
    }

    /// This object minus every element of `identifier` typed `role`, and minus `identifier` if it is left empty.
    private func removingIdentifiers(role: GroveIdentifierRole) throws(ExchangeIdentityError) -> LosslessJSONValue {
        try removingElements(of: "identifier") { $0.isIdentifier(role: role) }
    }

    private func removingElements(
        of name: String,
        where isRemoved: (LosslessJSONValue) -> Bool
    ) throws(ExchangeIdentityError) -> LosslessJSONValue {
        guard case .object(var members) = self, let value = members[name] else {
            return self
        }
        guard case .array(let elements) = value else {
            throw .invalidDigestContent("\(name) is a JSON array")
        }
        let kept = elements.filter { !isRemoved($0) }
        members[name] = kept.isEmpty ? nil : .array(kept)
        return .object(members)
    }

    private func isIdentifier(role: GroveIdentifierRole) -> Bool {
        guard case .object(let identifier) = self,
              case .object(let type)? = identifier["type"],
              case .array(let codings)? = type["coding"] else {
            return false
        }
        return codings.contains { coding in
            guard case .object(let members) = coding,
                  case .string(let system)? = members["system"],
                  case .string(let code)? = members["code"] else {
                return false
            }
            return system == Canonicals.identifierRoleCodeSystemValue && code == role.rawValue
        }
    }
}
