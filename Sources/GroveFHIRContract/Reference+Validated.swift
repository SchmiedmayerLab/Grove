//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import ModelsR4


/// Stable identity used to detect exact duplicate logical references.
public enum TypedReferenceIdentity: Hashable, Sendable {
    case identifier(type: ResourceType, identifier: BusinessIdentifier)
}


/// A fail-closed typed-reference validation failure.
public enum TypedReferenceError: Error, Equatable, Sendable {
    /// The reference is empty, ambiguous, malformed, or targets another resource type.
    case invalidReference(expectedResourceType: ResourceType)
    /// A literal cannot resolve where no Bundle entry travels with it.
    case literalRequiresBundleEntry(String)
}


extension Reference {
    /// The identity of an identifier-only logical reference to the expected resource type.
    ///
    /// Conversion inputs do not carry the referenced resource, so a literal cannot satisfy the
    /// exchange Bundle's closed-reference rule; graph assemblers mint internal literals only after
    /// their target entry and deterministic fullUrl both exist.
    public func validated(as resourceType: ResourceType) throws(TypedReferenceError) -> TypedReferenceIdentity {
        let literal = reference?.value?.string
        guard literal == nil || identifier == nil else {
            throw .invalidReference(expectedResourceType: resourceType)
        }
        if let literal {
            throw .literalRequiresBundleEntry(literal)
        }
        guard let identifier,
              type?.value?.url.absoluteString == resourceType.rawValue,
              let businessIdentifier = try? BusinessIdentifier(identifier) else {
            throw .invalidReference(expectedResourceType: resourceType)
        }
        return .identifier(type: resourceType, identifier: businessIdentifier)
    }
}


extension BundleEntry {
    /// An exchange entry keyed by its complete identifier, at the deterministic fullUrl that identifier names.
    public init(identifier: RoledIdentifier, resource: ResourceProxy) throws(ExchangeIdentityError) {
        self.init(
            extension: [Extension(url: Canonicals.entryNodeKey, value: .identifier(identifier.fhirIdentifier))],
            fullUrl: try identifier.fullURL,
            resource: resource
        )
    }
}
