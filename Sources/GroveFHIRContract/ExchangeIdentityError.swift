//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

public import Foundation


/// Why an identity, an identifier or an exchange event could not be formed or read: one error for every identity the
/// contract mints or validates, from the deployment's systems and key to a graph's entry keys.
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
    /// Two of the deployment's identity systems are the same system.
    case reusedIdentifierSystem
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
    case invalidCodeToken(field: String, value: String)
    case providerKindRequired(String)
    /// An identity kind received another number of components than its preimage has.
    case invalidComponentCount(kind: String, expected: Int, actual: Int)
    /// One identity component is longer than the length framing can state.
    case identityComponentTooLarge(Int)
    case invalidNonnegativeDecimal(String)
    case invalidProducerInstance(UUID)
    case invalidEventIdentifier(String)
    case invalidEventSequence(String)
    case duplicateEntryIdentifier(BusinessIdentifier)
    case invalidEntryNodeRole
    case invalidEntryNodeValue(String)
    case invalidNamespace(String)
    case invalidInstant

    /// The registered diagnostic, the same on every platform for the same fault.
    ///
    /// A stored event identifier out of its canonical form is the fault a record can carry, and an empty component is
    /// source metadata the record lacks. A part index is computed by the converter, so a non-canonical one is a producer
    /// defect, as is every other fault, deployment configuration included.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .invalidEventIdentifier:
            ExchangeGraphRule.mobileExchangeEventIdentity.diagnostic
        case .emptyComponent(let path):
            ExchangeGraphRule.mobileInputRequiredMetadataMissing.diagnostic(at: path)
        case .nonCanonicalPartIndex(let path):
            ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: path)
        default:
            ExchangeGraphRule.mobileInputUnclassified.diagnostic
        }
    }
}
