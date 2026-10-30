//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Failures raised before an opaque identifier can be minted.
///
/// A component fault names the component by its path, `<identity-kind>.<component>` as the catalog spells them.
public enum OpaqueIdentityError: Error, Equatable, Sendable {
    case invalidKeyID(String)
    case keyTooShort(actualBytes: Int)
    case publishedConformanceKeyProhibited
    /// A component the identity kind requires is empty.
    case emptyComponent(String)
    /// A part index is not a canonical unsigned decimal: it carries a sign, whitespace or a leading zero.
    case nonCanonicalPartIndex(String)
    case invalidCodeToken(field: String, value: String)
    case providerKindRequired(String)
    case reusedIdentifierSystem
    case componentTooLarge(byteCount: Int)
    case invalidComponentCount(kind: OpaqueIdentityKind, expected: Int, actual: Int)

    /// The registered diagnostic, the same on every platform for the same fault.
    ///
    /// An empty component is source metadata the record lacks. A part index is computed by the converter, so a
    /// non-canonical one is a producer defect, as is every deployment configuration fault.
    public var diagnostic: ProducerDiagnostic {
        switch self {
        case .emptyComponent(let path):
            ExchangeGraphRule.mobileInputRequiredMetadataMissing.diagnostic(at: path)
        case .nonCanonicalPartIndex(let path):
            ExchangeGraphRule.mobileInputUnclassified.diagnostic(at: path)
        case .invalidKeyID, .keyTooShort, .publishedConformanceKeyProhibited, .invalidCodeToken, .providerKindRequired,
             .reusedIdentifierSystem, .componentTooLarge, .invalidComponentCount:
            ExchangeGraphRule.mobileInputUnclassified.diagnostic
        }
    }
}
