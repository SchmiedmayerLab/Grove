//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// FHIR R4 initializers expose profile cardinalities directly; keeping those fields adjacent makes
// the clinical projection auditable against the IG even when a builder exceeds generic style limits.
// swiftlint:disable function_body_length function_parameter_count multiline_function_chains multiline_literal_brackets

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


extension GroveSensorKitFHIRConverter {
    static let ucum: FHIRPrimitive<FHIRURI> = "http://unitsofmeasure.org"
    static let lifecycle: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/iso-21089-lifecycle"
    static let participantType: FHIRPrimitive<FHIRURI> =
        "http://terminology.hl7.org/CodeSystem/provenance-participant-type"

    static func buildObservations(
        _ record: GroveSensorKitFHIRRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputNode: OutputNode?,
        rawURL: String?,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> [Observation] {
        guard let outputNode else {
            return []
        }
        let observation: Observation
        switch record {
        case .rotationRate(let record):
            observation = try rotationRateObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputNode.identifier,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .electrocardiogram(let record):
            guard let rawURL else {
                throw GroveSensorKitFHIRRecordError.sourceTypeHasNoRawContract("SRSensor.electrocardiogram")
            }
            observation = try ecgObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputNode.identifier,
                rawURL: rawURL,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .onWrist(let record):
            observation = try onWristObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputNode.identifier,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .deviceUsage(let record):
            guard let rawURL else {
                throw GroveSensorKitFHIRRecordError.sourceTypeHasNoRawContract("SRSensor.deviceUsageReport")
            }
            observation = try deviceUsageObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputNode.identifier,
                rawURL: rawURL,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .visit(let record):
            observation = try visitObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputNode.identifier,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .messagesUsage, .phoneUsage, .keyboardMetrics, .sleepSession, .accelerometer, .ppg:
            observation = try summaryObservation(
                record,
                sourceIdentifier: sourceIdentifier,
                outputIdentifier: outputNode.identifier,
                rawURL: rawURL,
                context: context,
                recordingDeviceURL: recordingDeviceURL,
                converterURL: converterURL
            )
        case .raw:
            return []
        }
        return [observation]
    }

    static func buildDocument(
        _ record: GroveSensorKitFHIRRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputNode: OutputNode?,
        relatedURLs: [String],
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> DocumentReference? {
        guard let outputNode, let native = record.nativeRecording else {
            return nil
        }
        let entry = try catalogEntry(sourceToken: record.sourceToken)
        var authors = recordingDeviceURL.map { [reference($0)] } ?? []
        authors.append(reference(converterURL))
        let related = relatedURLs.map(reference) + context.researchStudies
        var document = DocumentReference(
            author: authors,
            content: [DocumentReferenceContent(
                attachment: try attachment(native),
                format: try recordingFormat(native.format, entry: entry)
            )],
            context: related.isEmpty ? nil : DocumentReferenceContext(related: related),
            date: FHIRPrimitive(try exactInstant(context.recordedAt, timeZone: context.sourceTimeZone)),
            identifier: [sourceIdentifier.fhirIdentifier, outputNode.identifier.fhirIdentifier],
            meta: Meta(profile: entry.rawProfiles.map(profile)),
            status: FHIRPrimitive(.current),
            subject: context.subject,
            type: CodeableConcept(coding: [Coding(
                code: entry.sourceTypeCode.asFHIRStringPrimitive(),
                system: GroveSensorKitContract.sourceTypeCodeSystem.asFHIRURIPrimitive()
            )])
        )
        document.extension = [sourceTypeExtension(entry.sourceTypeCode)]
        return document
    }

    private static func rotationRateObservation(
        _ record: GroveSensorKitRotationRateRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        guard record.samples.count >= 2 else {
            throw GroveSensorKitFHIRRecordError.emptySamples
        }
        let instants = try record.samples.enumerated().map { index, sample in
            for (field, value) in [("x", sample.x), ("y", sample.y), ("z", sample.z)] where !value.isFinite {
                throw GroveSensorKitFHIRRecordError.nonFiniteValue(field: field, index: index)
            }
            return try epochDecimal(sample.timestamp, field: "timestamp", index: index)
        }
        let periodSeconds = instants[1] - instants[0]
        guard periodSeconds > 0 else {
            throw GroveSensorKitFHIRRecordError.nonUniformTiming(index: 1)
        }
        for index in instants.indices.dropFirst(2)
        where instants[index] != instants[0] + Decimal(index) * periodSeconds {
            throw GroveSensorKitFHIRRecordError.nonUniformTiming(index: index)
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.rotationRate")
        var observation = try baseObservation(
            code: Coding(
                code: entry.sourceTypeCode.asFHIRStringPrimitive(),
                display: "Rotation rate".asFHIRStringPrimitive(),
                system: GroveSensorKitContract.sourceTypeCodeSystem.asFHIRURIPrimitive()
            ),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try period(
            start: record.samples[0].timestamp,
            end: record.samples[record.samples.count - 1].timestamp,
            timeZone: context.sourceTimeZone
        ))
        observation.value = .sampledData(SampledData(
            data: try record.samples.flatMap { [$0.x, $0.y, $0.z] }.enumerated().map {
                try plainDecimal($0.element, field: "rotation-rate", index: $0.offset)
            }.joined(separator: " ").asFHIRStringPrimitive(),
            dimensions: 3,
            origin: quantity(value: 0, code: "rad/s", unit: nil),
            period: FHIRPrimitive(FHIRDecimal(periodSeconds * 1_000))
        ))
        return observation
    }

    private static func ecgObservation(
        _ record: GroveSensorKitECGRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        let validated = try validateECG(record)
        let entry = try catalogEntry(sourceToken: "SRSensor.electrocardiogram")
        var observation = try baseObservation(
            code: Coding(
                code: "11524-6".asFHIRStringPrimitive(),
                display: "EKG study".asFHIRStringPrimitive(),
                system: "http://loinc.org".asFHIRURIPrimitive()
            ),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.extension?.append(Extension(
            url: FHIRPrimitive(FHIRURI(
                stringLiteral: GroveSensorKitContract.ecgSessionGuidanceExtension
            )),
            value: .code(record.guidance.rawValue.asFHIRStringPrimitive())
        ))
        observation.effective = .period(Period(
            end: FHIRPrimitive(try exactDateTime(
                record.startDate,
                offsetSeconds: validated.lastOffsetSeconds,
                timeZone: context.sourceTimeZone
            )),
            start: FHIRPrimitive(try exactDateTime(
                record.startDate,
                offsetSeconds: 0,
                timeZone: context.sourceTimeZone
            ))
        ))
        observation.derivedFrom = [reference(rawURL)]
        var leadCodings = [Coding(
            code: record.lead.rawValue.asFHIRStringPrimitive(),
            display: (record.lead == .leftArmMinusRightArm
                ? "Left arm minus right arm"
                : "Right arm minus left arm").asFHIRStringPrimitive(),
            system: GroveSensorKitContract.ecgLeadCodeSystem.asFHIRURIPrimitive()
        )]
        if record.lead == .leftArmMinusRightArm {
            leadCodings.append(Coding(
                code: "131329".asFHIRStringPrimitive(),
                display: "MDC_ECG_ELEC_POTL_I".asFHIRStringPrimitive(),
                system: "urn:iso:std:iso:11073:10101".asFHIRURIPrimitive()
            ))
        }
        observation.component = [ObservationComponent(
            code: CodeableConcept(coding: leadCodings),
            value: .sampledData(SampledData(
                data: validated.data.asFHIRStringPrimitive(),
                dimensions: 1,
                origin: quantity(value: 0, code: "mV", unit: nil),
                period: FHIRPrimitive(FHIRDecimal(validated.periodMilliseconds))
            ))
        )]
        return observation
    }

    private static func onWristObservation(
        _ record: GroveSensorKitOnWristRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        guard record.currentStateStart <= record.timestamp else {
            throw GroveSensorKitFHIRRecordError.invalidCurrentStatePeriod
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.onWristState")
        var observation = try baseObservation(
            code: conceptCoding("on-wrist-state", "On-wrist state"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        if record.currentStateStart == record.timestamp {
            observation.effective = .dateTime(FHIRPrimitive(try exactDateTime(
                record.timestamp,
                timeZone: context.sourceTimeZone
            )))
        } else {
            observation.effective = .period(try period(
                start: record.currentStateStart,
                end: record.timestamp,
                timeZone: context.sourceTimeZone
            ))
        }
        observation.value = .codeableConcept(valueConcept(
            record.onWrist ? "on-wrist" : "off-wrist",
            record.onWrist ? "On wrist" : "Off wrist"
        ))
        observation.component = [
            codedComponent(
                code: "wrist-location",
                display: "Wrist location",
                value: record.wristLocation.rawValue,
                valueDisplay: record.wristLocation.rawValue.capitalized
            ),
            codedComponent(
                code: "crown-orientation",
                display: "Crown orientation",
                value: record.crownOrientation.rawValue,
                valueDisplay: record.crownOrientation.rawValue.capitalized
            )
        ]
        return observation
    }

    private static func deviceUsageObservation(
        _ record: GroveSensorKitDeviceUsageRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        rawURL: String,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        guard record.durationSeconds.isFinite, record.durationSeconds > 0,
              record.totalUnlockDurationSeconds.isFinite,
              record.totalUnlockDurationSeconds >= 0,
              record.totalUnlockDurationSeconds <= record.durationSeconds else {
            throw GroveSensorKitFHIRRecordError.invalidDeviceUsagePeriod
        }
        for (field, value) in [
            ("totalScreenWakes", record.totalScreenWakes),
            ("totalUnlocks", record.totalUnlocks)
        ] where value < 0 || Int32(exactly: value) == nil {
            throw GroveSensorKitFHIRRecordError.invalidDeviceUsageCount(field: field, value: value)
        }
        let duration = try decimal(record.durationSeconds, field: "duration", index: nil)
        let entry = try catalogEntry(sourceToken: "SRSensor.deviceUsageReport")
        var observation = try baseObservation(
            code: conceptCoding("device-usage-summary", "Device usage summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(Period(
            end: FHIRPrimitive(try exactDateTime(
                record.timestamp,
                offsetSeconds: duration,
                timeZone: context.sourceTimeZone
            )),
            start: FHIRPrimitive(try exactDateTime(record.timestamp, timeZone: context.sourceTimeZone))
        ))
        observation.value = .quantity(quantity(
            value: try decimal(record.totalUnlockDurationSeconds, field: "totalUnlockDuration", index: nil),
            code: "s",
            unit: "seconds"
        ))
        observation.component = [
            quantityComponent(
                code: "screen-wakes",
                display: "Screen wakes",
                value: Decimal(record.totalScreenWakes),
                unitCode: "{count}"
            ),
            quantityComponent(
                code: "unlocks",
                display: "Unlocks",
                value: Decimal(record.totalUnlocks),
                unitCode: "{count}"
            )
        ]
        observation.derivedFrom = [reference(rawURL)]
        return observation
    }

    private static func visitObservation(
        _ record: GroveSensorKitVisitRecord,
        sourceIdentifier: GroveFHIRBusinessIdentifier,
        outputIdentifier: GroveFHIRBusinessIdentifier,
        context: GroveSensorKitFHIRConversionContext,
        recordingDeviceURL: String?,
        converterURL: String
    ) throws -> Observation {
        guard record.arrivalWindow.start <= record.arrivalWindow.end,
              record.departureWindow.start <= record.departureWindow.end,
              record.arrivalWindow.start <= record.departureWindow.end,
              record.distanceFromHomeMeters.isFinite,
              record.distanceFromHomeMeters >= 0 else {
            throw GroveSensorKitFHIRRecordError.invalidVisitPeriod
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.visits")
        var observation = try baseObservation(
            code: conceptCoding("visit-summary", "Visit summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode,
            sourceIdentifier: sourceIdentifier,
            outputIdentifier: outputIdentifier,
            context: context,
            recordingDeviceURL: recordingDeviceURL,
            converterURL: converterURL
        )
        observation.effective = .period(try period(
            start: record.arrivalWindow.start,
            end: record.departureWindow.end,
            timeZone: context.sourceTimeZone
        ))
        observation.component = [
            codedComponent(
                code: "visit-location-category",
                display: "Visit location category",
                value: record.locationCategory.rawValue,
                valueDisplay: record.locationCategory.rawValue.capitalized
            ),
            quantityComponent(
                code: "distance-from-home",
                display: "Distance from home",
                value: try decimal(record.distanceFromHomeMeters, field: "distanceFromHome", index: nil),
                unitCode: "m"
            ),
            try periodComponent(
                code: "arrival-window",
                display: "Arrival window",
                interval: record.arrivalWindow,
                timeZone: context.sourceTimeZone
            ),
            try periodComponent(
                code: "departure-window",
                display: "Departure window",
                interval: record.departureWindow,
                timeZone: context.sourceTimeZone
            )
        ]
        return observation
    }
}
