//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import Foundation
public import GroveFHIRContract
public import HealthKit


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    private static func nativeRecordID(of record: HealthKitSourceRecord) -> String {
        record.uuid.uuidString.lowercased()
    }

    private static func sourceRecord(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> SourceRecordIdentity {
        do {
            return try context.identityScope.sourceRecord(
                adapterID: adapterID,
                sourceType: record.type.rawValue,
                repositoryScope: context.repositoryScope,
                nativeRecordID: nativeRecordID(of: record)
            )
        } catch {
            throw .opaqueIdentity(error)
        }
    }

    /// The complete retraction of a deleted record, as its own exchange event.
    ///
    /// `context` is a fresh context for the retraction's event, under the same identity scope,
    /// repository scope and native-identifier disclosure as the record's conversion. The source
    /// record and every target are recomputed from `record`, so nothing from that conversion needs
    /// to be kept.
    public func retraction(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext,
        retractedAt: Date
    ) throws(HealthKitConversionError) -> RetractionEvent {
        let targets = try retractionTargets(for: record, context: context)
        let sourceRecord = try Self.sourceRecord(for: record, context: context)
        do throws(RetractionEventError) {
            return try RetractionEvent(
                targets: targets,
                context: context.event,
                sourceRecord: sourceRecord.identifier,
                retractedAt: retractedAt
            )
        } catch {
            throw HealthKitConversionError(error)
        }
    }

    /// The logical targets a deletion retracts, named from the catalog alone.
    ///
    /// A deleted sample is gone, so the outputs its addition minted are recomputed from the source
    /// type: the same identity scope and the same output roles yield the same identifiers. The
    /// sample's UUID rides along as each target's native record identifier exactly when the
    /// context's native-identifier disclosure authorizes it on the addition path.
    public func retractionTargets(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> [RetractionTarget] {
        try Self.validate(context: context)
        let outputs = HealthKitCatalog.outputs(for: record.type)
        guard !outputs.isEmpty else {
            throw Self.unconvertibleSampleError(for: record.type)
        }
        let nativeRecordIdentifier = context.options.nativeIdentifierDisclosure.nativeRecordIdentifier(
            for: Self.nativeRecordID(of: record)
        )
        let sourceRecord = try Self.sourceRecord(for: record, context: context)
        var targets: [RetractionTarget] = []
        for output in outputs {
            let identity: RoledIdentifier
            do {
                identity = try sourceRecord.output(role: output.role, discriminator: output.discriminator)
            } catch {
                throw .opaqueIdentity(error)
            }
            do {
                targets.append(try RetractionTarget(
                    identifier: identity,
                    resourceType: output.resourceType,
                    role: output.retractionRole,
                    nativeRecordIdentifier: nativeRecordIdentifier
                ))
            } catch {
                throw .dependency(HealthKitDependencyFailure(underlying: error))
            }
        }
        return targets
    }
}


extension HealthKitSourceType {
    /// The inventory row of a sample type, such as the one a deletion was reported for.
    public init?(_ sampleType: HKSampleType) {
        self.init(rawValue: sampleType.identifier)
    }
}


extension HealthKitConversionError {
    init(_ error: RetractionEventError) {
        self = switch error {
        case .reservedIdentifierSystem: .reservedIdentifierSystem
        case .opaqueIdentity(let error): .opaqueIdentity(error)
        case .exchangeIdentity(let error): .exchangeIdentity(error)
        case .exchangeGraph(let error): .exchangeGraph(error)
        case .emptyTargets, .duplicateTarget, .invalidSourceRecord, .invalidInstant:
            .dependency(HealthKitDependencyFailure(underlying: error))
        }
    }
}

#endif
