//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The source-record identity of one native record, from which its output and artifact identities are minted.
///
/// Their preimages extend the record's components with their own, so neither restates the record. A provider-owned
/// record mints under the provider identity kinds, in the same `source-*` roles.
/// Debug output prints the opaque identifier only, never the native record identifier.
@DebugDescription
public struct SourceRecordIdentity: Sendable, CustomDebugStringConvertible {
    /// The typed `source-record` identifier.
    public let identifier: RoledIdentifier
    private let scope: OpaqueIdentityScope
    private let components: [String]
    /// The kinds the record's outputs and artifacts mint under: `source-*`, or `provider-*` for a provider-owned record.
    private let outputKind: OpaqueIdentityKind
    private let artifactKind: OpaqueIdentityKind

    public var debugDescription: String {
        "SourceRecordIdentity(identifier: \(identifier.identifier.value))"
    }

    /// The identity of a native source record, or under `isProviderRecord` of a provider-owned one.
    init(scope: OpaqueIdentityScope, components: [String], isProviderRecord: Bool = false) throws(ExchangeIdentityError) {
        self.identifier = try scope.identifier(kind: isProviderRecord ? .providerRecord : .sourceRecord, components: components)
        self.scope = scope
        self.components = components
        self.outputKind = isProviderRecord ? .providerOutput : .sourceOutput
        self.artifactKind = isProviderRecord ? .providerArtifact : .sourceArtifact
    }

    /// The `source-output` identifier of one output this record converts to.
    public func output(role: String, discriminator: String) throws(ExchangeIdentityError) -> RoledIdentifier {
        try scope.output(extending: components, kind: outputKind, role: role, discriminator: discriminator)
    }

    /// The `source-artifact` identifier of one part of the record's native artifact.
    package func artifact(formatCode: String, partIndex: CanonicalNonnegativeDecimal) throws(ExchangeIdentityError) -> RoledIdentifier {
        try scope.artifact(extending: components, kind: artifactKind, formatCode: formatCode, partIndex: partIndex)
    }

    /// Convenience for a locally machine-sized part index.
    package func artifact(formatCode: String, partIndex: UInt64) throws(ExchangeIdentityError) -> RoledIdentifier {
        try artifact(formatCode: formatCode, partIndex: CanonicalNonnegativeDecimal(partIndex))
    }
}
