//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

extension OpaqueIdentityScope {
    /// Mints the identity of one native source record; its output and artifact identities extend it.
    public func sourceRecord(
        adapterID: String,
        sourceType: String,
        repositoryScope: BusinessIdentifier,
        nativeRecordID: String
    ) throws(OpaqueIdentityError) -> SourceRecordIdentity {
        try SourceRecordIdentity(
            scope: self,
            components: [
                adapterID,
                sourceType,
                repositoryScope.system.rawValue,
                repositoryScope.value,
                nativeRecordID
            ]
        )
    }

    /// Mints the identity of one provider-owned record; its output and artifact identities extend it.
    public func providerRecord(
        providerCode: GroveProviderCode,
        sourceType: String,
        providerScope: BusinessIdentifier,
        nativeRecordID: String
    ) throws(OpaqueIdentityError) -> ProviderRecordIdentity {
        try ProviderRecordIdentity(
            scope: self,
            components: [
                providerCode.rawValue,
                sourceType,
                providerScope.system.rawValue,
                providerScope.value,
                nativeRecordID
            ]
        )
    }

    /// Identifies the logical record the writer application assigned, when the platform supplies it.
    public func writerRecord(
        writerApplication: BusinessIdentifier,
        writerRecordID: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try identifier(
            kind: .writerRecord,
            components: [
                writerApplication.system.rawValue,
                writerApplication.value,
                writerRecordID
            ]
        )
    }

    /// Identifies source-owned context referenced by more than one emitted record.
    ///
    /// For example, HealthKit medication statements and dose events use this identity for the
    /// same `HKHealthConceptIdentifier` without disclosing that platform identifier on the wire.
    public func sourceContext(
        adapterID: String,
        contextType: String,
        repositoryScope: BusinessIdentifier,
        nativeContextID: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateCodeToken(contextType, field: "source-context.context-type")
        return try identifier(
            kind: .sourceContext,
            components: [
                adapterID,
                contextType,
                repositoryScope.system.rawValue,
                repositoryScope.value,
                nativeContextID
            ]
        )
    }

    func output(
        extending record: [String],
        kind: OpaqueIdentityKind,
        role: String,
        discriminator: String
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try validateCodeToken(role, field: "\(kind.rawValue).output-role")
        return try identifier(kind: kind, components: record + [role, discriminator])
    }

    func artifact(
        extending record: [String],
        kind: OpaqueIdentityKind,
        formatCode: String,
        partIndex: CanonicalNonnegativeDecimal
    ) throws(OpaqueIdentityError) -> RoledIdentifier {
        try identifier(kind: kind, components: record + [formatCode, partIndex.rawValue])
    }
}
