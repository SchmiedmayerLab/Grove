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

    /// One recording document of today's builder under `sample`'s envelope, whatever the sample's own type.
    static func assembleDocumentGraph(
        for sample: HKSample,
        evidence: HealthKitRecordingEvidence,
        context: HealthKitConversionContext
    ) throws -> HealthKitConversionSet {
        try validate(context: context)
        guard let plan = HealthKitContentPlan.plan(for: sample) else {
            throw HealthKitConversionError.unregisteredSourceType(sample.sampleType.identifier)
        }
        let output = ExchangeOutputDraft(
            role: evidence.outputRole,
            resource: .document(try recordingDocument(evidence: evidence, sourceTypeIdentifier: sample.sampleType.identifier)),
            links: [.subject, .recordingDevice, .studies],
            artifactFormatCode: evidence.format.rawValue
        )
        let conversion = try HealthKitAssembly(context: context.event).graph(
            for: sample,
            type: plan.sourceType,
            metadata: HealthKitSampleMetadata(sample, rule: plan.metadata),
            outputs: [output],
            request: .init(context: context)
        )
        return HealthKitConversionSet(primary: conversion)
    }

    /// The route's track, or `nil` when the context does not authorize disclosing one.
    static func locationTrackPayload(_ locations: [CLLocation], context: HealthKitConversionContext) throws -> Data? {
        guard context.options.routeDisclosure == .authorized else {
            return nil
        }
        return try locationTrackPayload(locations)
    }
}

#endif
