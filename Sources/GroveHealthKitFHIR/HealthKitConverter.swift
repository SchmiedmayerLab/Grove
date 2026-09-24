//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
public import GroveFHIRContract
import GroveHealthKit
public import HealthKit
import ModelsR4


/// Profile-aware HealthKit-to-FHIR R4 facade.
///
/// The converter consumes already-fetched `HKSample` values. It does not query HealthKit,
/// authorize data access, synchronize anchors, persist resources, or upload anything.
@available(iOS 18, macOS 15, watchOS 11, *)
public struct HealthKitConverter: Sendable {
    public init() {}

    /// Converts one sample only when the closed catalog admits its exact published contract.
    public func convert(
        _ sample: HKSample,
        context: HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            return try Self.convertSample(sample, context: context)
        } catch {
            throw HealthKitConversionError(conversionFailure: error, source: HealthKitSourceType(sample))
        }
    }

    /// Converts every input and keeps a typed failure for every record that was not emitted.
    ///
    /// A record whose context the caller could not supply fails with the caller's own error and
    /// never becomes a conversion refusal.
    public func convert<E: Error>(
        _ samples: some Sequence<HKSample>,
        context: (HKSample) throws(E) -> HealthKitConversionContext
    ) -> ConversionBatch<HealthKitConversionSet, HealthKitRecordFailure<E>> {
        var conversions: [HealthKitConversionSet] = []
        var failures: [HealthKitRecordFailure<E>] = []
        for sample in samples {
            guard let type = HealthKitSourceType(sample) else {
                failures.append(.unregisteredSourceType(uuid: sample.uuid, identifier: sample.sampleType.identifier))
                continue
            }
            let record = HealthKitSourceRecord(uuid: sample.uuid, type: type)
            let sampleContext: HealthKitConversionContext
            do {
                sampleContext = try context(sample)
            } catch {
                failures.append(.context(record, error))
                continue
            }
            do {
                conversions.append(try convert(sample, context: sampleContext))
            } catch {
                failures.append(.conversion(record, error))
            }
        }
        return ConversionBatch(conversions: conversions, failures: failures)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// The closed adapter token every HealthKit identity preimage carries.
    static let adapterID = "healthkit"

    static func convertSample(
        _ sample: HKSample,
        context: HealthKitConversionContext
    ) throws -> HealthKitConversionSet {
        try validate(context: context)
        guard let type = HealthKitSourceType(sample) else {
            throw HealthKitConversionError.unregisteredSourceType(sample.sampleType.identifier)
        }
        if sample is HKElectrocardiogram {
            throw HealthKitConversionError.ecgEvidence(.evidenceRequired)
        }
        #if !os(watchOS)
        if let record = sample as? HKClinicalRecord {
            return try convertClinicalRecord(record, context: context)
        }
        if let document = sample as? HKCDADocumentSample {
            return try convertClinicalDocument(document, context: context)
        }
        #endif
        guard let binding = HealthKitCatalog.binding(for: sample),
              let output = HealthKitCatalog.primaryOutput(for: type) else {
            throw unconvertibleSampleError(for: type)
        }
        return try assembleGraph(
            for: sample,
            context: context,
            outputRole: output.role,
            outputDiscriminator: output.discriminator,
            childBuilder: (sample as? HKWorkout).map(workoutChildBuilder(for:))
        ) { graphContext in
            try observation(for: sample, binding: binding, graphContext: graphContext)
        }
    }

    /// A workout's segments hang off its session totals as `hasMember` children.
    private static func workoutChildBuilder(for workout: HKWorkout) -> (GraphEnvelope) throws -> [GraphChildOutput] {
        { envelope in
            try workoutSegments(workout, envelope: envelope).map { segment in
                GraphChildOutput(
                    identity: segment.identity,
                    observation: segment.observation,
                    primaryRelationship: .hasMember
                )
            }
        }
    }

    /// The catalog-driven reason a sample without a binding fails closed.
    static func unconvertibleSampleError(for type: HealthKitSourceType) -> HealthKitConversionError {
        if type == .bloodPressureSystolic || type == .bloodPressureDiastolic {
            return .componentRequiresCorrelation(type)
        }
        let entry = HealthKitCatalog[type]
        switch entry.implementationStatus {
        case .intentionallyUnsupported:
            return .intentionallyUnsupported(type, reason: entry.requirement ?? "")
        case .platformExclusive:
            return .platformExclusiveSourceType(type)
        case .supported where type == .workout:
            return .notYetConvertible(type)
        case .supported:
            return .unsupportedSourceType(type)
        }
    }
}

#endif
