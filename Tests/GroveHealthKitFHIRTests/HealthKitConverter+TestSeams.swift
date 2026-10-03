//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import CoreLocation
import Foundation
import GroveFHIRContract
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


/// The internal seams the tests were written against, expressed through the assembly that replaced
/// them; each states what the assembly does for one context-shaped input.
extension HealthKitConverter {
    /// A writer's application and host snapshots, deduplicated against the converter's own.
    struct WriterDevices {
        let application: IdentifiedDevice
        let host: IdentifiedDevice

        func entries(excluding stated: Set<RoledIdentifier>) -> [IdentifiedDevice] {
            ExchangeGraphAssembler.writerEntries(application: application, host: host, stated: stated)
        }
    }

    static func convertSample(_ sample: HKSample, context: HealthKitConversionContext) throws -> HealthKitConversionSet {
        try validate(context: context)
        return try HealthKitAssembly(context: context.event).convert(sample, request: .init(context: context))
    }

    static func retraction(
        for record: HealthKitSourceRecord,
        context: HealthKitConversionContext,
        occurred: RetractionOccurrence
    ) throws -> RetractionEvent {
        try HealthKitAssembly(context: context.event).retraction(of: record, request: .init(context: context), occurred: occurred)
    }

    /// `ecg` supplies only the envelope's identity, device and source facts; the evidence is given.
    static func convertECG(
        _ ecg: HKSample,
        evidence: HealthKitECGEvidence,
        symptoms: [HKCategorySample],
        context: HealthKitConversionContext,
        symptomContexts: [HealthKitConversionContext]
    ) throws -> HealthKitConversionSet {
        try HealthKitAssembly(context: context.event).convertECG(
            ecg,
            evidence: evidence,
            symptoms: symptoms,
            request: .init(context: context),
            symptomRequests: symptomContexts.map { .init(context: $0) }
        )
    }

    /// One recording document under `sample`'s envelope, whatever the sample's own type.
    static func assembleDocumentGraph(
        for sample: HKSample,
        evidence: HealthKitRecordingEvidence,
        context: HealthKitConversionContext
    ) throws -> HealthKitConversionSet {
        try validate(context: context)
        guard let type = HealthKitSourceType(sample) else {
            throw HealthKitConversionError.unregisteredSourceType(sample.sampleType.identifier)
        }
        return try HealthKitAssembly(context: context.event).documentGraph(for: sample, type: type, evidence: evidence, request: .init(context: context))
    }

    /// The route's track, or `nil` when the context does not authorize disclosing one.
    static func locationTrackPayload(_ locations: [CLLocation], context: HealthKitConversionContext) throws -> Data? {
        guard context.options.routeDisclosure == .authorized else {
            return nil
        }
        return try locationTrackPayload(locations)
    }

    // HealthKit itself models the metadata dictionary as absent when an object has no metadata.
    /// Applies Apple's paired sync metadata exactly as the assembler decorates an output with it.
    static func applySyncIdentity(
        metadata: [String: Any]?, // swiftlint:disable:this discouraged_optional_collection
        writerApplication: String,
        to observation: inout Observation,
        context: HealthKitConversionContext
    ) throws {
        guard let record = try HealthKitAssembly.SourceFacts.writerRecord(metadata: metadata, writerApplication: writerApplication) else {
            return
        }
        let identity = try context.identityScope.writerRecord(
            writerApplication: BusinessIdentifier(
                system: IdentifierSystem(Canonicals.appleBundleIdentifierSystem),
                value: record.writerApplication
            ),
            writerRecordID: record.syncIdentifier
        )
        observation.identifier = (observation.identifier ?? []) + [identity.fhirIdentifier]
        observation.extension = (observation.extension ?? []) + [
            Extension(url: Canonicals.writerRecordVersion, value: .string(record.version.asFHIRStringPrimitive()))
        ]
    }
}

#endif
