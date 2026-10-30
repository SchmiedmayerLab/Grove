//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The provider-record identity of one provider-owned record, from which its output and artifact identities are minted.
///
/// The provider counterpart of ``SourceRecordIdentity``: its `provider-output` and `provider-artifact`
/// identities carry the `source-output` and `source-artifact` roles.
/// Debug output prints the opaque identifier only, never the native record identifier.
@DebugDescription
public struct ProviderRecordIdentity: Sendable, CustomDebugStringConvertible {
    /// The typed `provider-record` identifier, in the `source-record` role.
    public let identifier: RoledIdentifier
    private let scope: OpaqueIdentityScope
    private let components: [String]

    public var debugDescription: String {
        "ProviderRecordIdentity(identifier: \(identifier.identifier.value))"
    }

    init(scope: OpaqueIdentityScope, components: [String]) throws(OpaqueIdentityError) {
        self.identifier = try scope.identifier(kind: .providerRecord, components: components)
        self.scope = scope
        self.components = components
    }

    /// The `provider-output` identifier of one output this record converts to.
    public func output(role: String, discriminator: String) throws(OpaqueIdentityError) -> RoledIdentifier {
        try scope.output(extending: components, kind: .providerOutput, role: role, discriminator: discriminator)
    }

    /// The `provider-artifact` identifier of one part of the record's native artifact.
    public func artifact(formatCode: String, partIndex: CanonicalNonnegativeDecimal) throws(OpaqueIdentityError) -> RoledIdentifier {
        try scope.artifact(extending: components, kind: .providerArtifact, formatCode: formatCode, partIndex: partIndex)
    }

    /// Convenience for a locally machine-sized part index.
    public func artifact(formatCode: String, partIndex: UInt64) throws(OpaqueIdentityError) -> RoledIdentifier {
        try artifact(formatCode: formatCode, partIndex: CanonicalNonnegativeDecimal(partIndex))
    }
}
