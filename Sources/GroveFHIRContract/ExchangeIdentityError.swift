//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Why an identity or an identifier could not be formed or read: one error for every identity the contract mints or
/// validates, from the deployment's systems and key to a graph's entry keys.
///
/// A component fault names the component by its path, `<identity-kind>.<component>` as the catalog spells them.
public enum ExchangeIdentityError: Error, Equatable, Sendable {
    case missingIdentifierSystem
    case missingIdentifierValue
    case invalidIdentifierSystem(String)
    case nonCanonicalIdentifierSystem(supplied: String, encoded: String)
    case invalidRepositoryID(String)
    case invalidKeyID(String)
    /// The exchange protocol's recommended identifier systems cannot be formed under this deployment root.
    case invalidDeploymentRoot(String)
    case keyTooShort(actualBytes: Int)
    case publishedConformanceKeyProhibited
    case invalidIdentifierRole(String)
    case duplicateIdentifierRole
    case identifierSystemRoleMismatch(
        system: String,
        first: GroveIdentifierRole,
        conflicting: GroveIdentifierRole
    )
    /// A component the identity kind requires is empty.
    case emptyComponent(String)
    /// A part index is not a canonical unsigned decimal: it carries a sign, whitespace or a leading zero.
    case nonCanonicalPartIndex(String)
    /// A digest component is not a SHA-256 digest in base64url without padding: 43 characters of `[A-Za-z0-9_-]`.
    case nonCanonicalDigest(String)
    /// A `node-role` component is not a role of its snapshot kind.
    case invalidNodeRole(String)
    /// A resource cannot enter a content or record-content digest; the text names what it lacks.
    case invalidDigestContent(String)
    case invalidCodeToken(field: String, value: String)
    case providerKindRequired(String)
    /// An identity kind received another number of components than its preimage has.
    case invalidComponentCount(kind: String, expected: Int, actual: Int)
    /// One identity component is longer than the length framing can state.
    case identityComponentTooLarge(Int)
    case invalidNonnegativeDecimal(String)
    case invalidKeyEpoch(String)
    /// A record version or retraction key is not a canonical opaque value.
    case invalidRecordVersion(String)
    case duplicateEntryIdentifier(BusinessIdentifier)
    case invalidNamespace(String)
    case invalidInstant

    /// The registered diagnostic, the same on every platform for the same fault.
    ///
    /// An empty component is source metadata the record lacks. A part index, a digest and a node role are computed by
    /// the converter, so a non-canonical one is a producer defect, as is every other fault, deployment configuration
    /// included.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .emptyComponent(let path):
            ExchangeGraphRule.mobileInputRequiredMetadataMissing.diagnostic(at: path)
        case .nonCanonicalPartIndex(let path), .nonCanonicalDigest(let path), .invalidNodeRole(let path):
            ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: path)
        default:
            ExchangeGraphRule.mobileInputUnclassified.diagnostic
        }
    }
}
