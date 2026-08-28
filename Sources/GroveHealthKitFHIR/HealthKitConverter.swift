//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import GroveFHIRContract
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
    ) throws(HealthKitConversionError) -> HealthKitConversion {
        do {
            return try Self.convertSample(sample, context: context)
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    /// Converts every input and returns a typed failure for every record that was not emitted.
    public func convert<S: Sequence>(
        _ samples: S,
        contextForSample: (HKSample) throws -> HealthKitConversionContext
    ) -> HealthKitBatchResult where S.Element == HKSample {
        var conversions: [HealthKitConversion] = []
        var failures: [HealthKitRecordFailure] = []
        for sample in samples {
            do {
                conversions.append(try convert(sample, context: contextForSample(sample)))
            } catch let error as HealthKitConversionError {
                failures.append(HealthKitRecordFailure(
                    sourceUUID: sample.uuid,
                    sourceTypeIdentifier: sample.sampleType.identifier,
                    reason: error
                ))
            } catch {
                failures.append(HealthKitRecordFailure(
                    sourceUUID: sample.uuid,
                    sourceTypeIdentifier: sample.sampleType.identifier,
                    reason: HealthKitConversionError(conversionFailure: error)
                ))
            }
        }
        return HealthKitBatchResult(conversions: conversions, failures: failures)
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    static let mdc: FHIRPrimitive<FHIRURI> = "urn:iso:std:iso:11073:10101"
    static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"
    static let lifecycleEvent: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"

    static func convertSample(
        _ sample: HKSample,
        context: HealthKitConversionContext
    ) throws -> HealthKitConversion {
        try validate(context: context)
        if sample is HKElectrocardiogram {
            throw HealthKitConversionError.missingECGEvidence
        }
        guard let binding = HealthKitCatalog.binding(for: sample) else {
            throw unconvertibleSampleError(forSourceTypeIdentifier: sample.sampleType.identifier)
        }
        let workoutChildren: ((GraphEnvelope) throws -> [GraphChildOutput])?
        if let workout = sample as? HKWorkout {
            workoutChildren = { envelope in
                try workoutSegments(
                    workout,
                    context: context,
                    sourceRecord: envelope.sourceRecord,
                    sourceUUID: envelope.sourceUUID
                ).map { segment in
                    GraphChildOutput(
                        identity: segment.identity,
                        observation: segment.observation,
                        primaryRelationship: .hasMember
                    )
                }
            }
        } else {
            workoutChildren = nil
        }
        return try assembleGraph(
            for: sample,
            context: context,
            outputRole: binding.contract.id,
            outputDiscriminator: sample is HKWorkout ? "session" : "single",
            childBuilder: workoutChildren
        ) { recordingDeviceURL, converterURL in
            try observation(
                for: sample,
                binding: binding,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        }
    }

    /// The catalog-driven reason a sample without a binding fails closed.
    static func unconvertibleSampleError(
        forSourceTypeIdentifier identifier: String
    ) -> HealthKitConversionError {
        guard let entry = HealthKitCatalog.entry(forSourceTypeIdentifier: identifier) else {
            return .unsupportedSampleType(identifier)
        }
        switch entry.implementationStatus {
        case .intentionallyUnsupported:
            return .intentionallyUnsupported(sampleType: identifier, reason: entry.requirement ?? "")
        case .platformExclusive:
            return .platformExclusiveDocument(sampleType: identifier)
        case .supported where identifier == HKWorkoutType.workoutType().identifier:
            return .notYetConvertible(sampleType: identifier)
        case .supported where identifier == HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue
            || identifier == HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return .componentSampleRequiresCorrelation(sampleType: identifier)
        case .supported:
            return .unsupportedSampleType(identifier)
        }
    }
}

#endif
