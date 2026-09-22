//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

public import GroveFHIRContract


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The logical targets a deletion retracts, named from the catalog alone.
    ///
    /// A deleted sample is gone, so the outputs its addition minted are recomputed from the source
    /// type: the same identity scope and the same output roles yield the same identifiers.
    public func retractionTargets(
        for record: HealthKitSourceRecord,
        context: ExchangeEventContext
    ) throws(HealthKitConversionError) -> [RetractionTarget] {
        let outputs = HealthKitCatalog.outputs(for: record.type)
        guard !outputs.isEmpty else {
            throw Self.unconvertibleSampleError(for: record.type)
        }
        var targets: [RetractionTarget] = []
        for output in outputs {
            let identity: RoledIdentifier
            do {
                identity = try context.identityScope.sourceOutput(
                    adapterID: Self.adapterID,
                    sourceType: record.type.rawValue,
                    repositoryScope: context.repositoryScope,
                    nativeRecordID: record.uuid.uuidString.lowercased(),
                    outputRole: output.role,
                    outputDiscriminator: output.discriminator
                )
            } catch {
                throw .opaqueIdentity(error)
            }
            do {
                targets.append(try RetractionTarget(
                    identifier: identity,
                    resourceType: output.resourceType,
                    role: output.retractionRole
                ))
            } catch {
                throw .dependency(HealthKitDependencyFailure(underlying: error))
            }
        }
        return targets
    }
}

#endif
