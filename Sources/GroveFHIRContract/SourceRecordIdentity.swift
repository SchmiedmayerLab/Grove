//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// The source-record identity of one native record, from which its output and artifact identities are minted.
///
/// Their preimages extend the record's components with their own, so neither restates the record.
/// Debug output prints the opaque identifier only, never the native record identifier.
@DebugDescription
public struct SourceRecordIdentity: Sendable, CustomDebugStringConvertible {
    /// The typed `source-record` identifier.
    public let identifier: RoledIdentifier
    private let scope: OpaqueIdentityScope
    private let components: [String]

    public var debugDescription: String {
        "SourceRecordIdentity(identifier: \(identifier.identifier.value))"
    }

    init(scope: OpaqueIdentityScope, components: [String]) throws(OpaqueIdentityError) {
        self.identifier = try scope.identifier(kind: .sourceRecord, components: components)
        self.scope = scope
        self.components = components
    }

    /// The `source-output` identifier of one output this record converts to.
    public func output(role: String, discriminator: String) throws(OpaqueIdentityError) -> RoledIdentifier {
        try scope.output(extending: components, kind: .sourceOutput, role: role, discriminator: discriminator)
    }

    /// The `source-artifact` identifier of one part of the record's native artifact.
    public func artifact(formatCode: String, partIndex: CanonicalNonnegativeDecimal) throws(OpaqueIdentityError) -> RoledIdentifier {
        try scope.artifact(extending: components, kind: .sourceArtifact, formatCode: formatCode, partIndex: partIndex)
    }

    /// Convenience for a locally machine-sized part index.
    public func artifact(formatCode: String, partIndex: UInt64) throws(OpaqueIdentityError) -> RoledIdentifier {
        try artifact(formatCode: formatCode, partIndex: CanonicalNonnegativeDecimal(partIndex))
    }
}
