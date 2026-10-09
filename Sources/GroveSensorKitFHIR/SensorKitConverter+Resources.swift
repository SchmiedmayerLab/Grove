//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

// FHIR R4 initializers expose profile cardinalities directly; keeping those fields adjacent makes
// the clinical projection auditable against the IG even when a builder exceeds generic style limits.
// swiftlint:disable function_body_length multiline_function_chains multiline_literal_brackets

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
import ModelsR4


extension SensorKitConverter {
    /// The structured Observation of a record whose catalog row names one; `rawURL` is the fullUrl of the
    /// record's raw output, when it has one.
    static func buildObservation(_ record: SensorKitRecord, rawURL: String?, context: ContentContext) throws -> Observation {
        switch record {
        case .rotationRate(let record):
            return try rotationRateObservation(record, context: context)
        case .electrocardiogram(let record):
            return try ecgObservation(record, rawURL: try requiredRawURL(rawURL, sourceToken: "SRSensor.electrocardiogram"), context: context)
        case .onWrist(let record):
            return try onWristObservation(record, context: context)
        case .deviceUsage(let record):
            return try deviceUsageObservation(record, rawURL: try requiredRawURL(rawURL, sourceToken: "SRSensor.deviceUsageReport"), context: context)
        case .visit(let record):
            return try visitObservation(record, context: context)
        case .messagesUsage, .phoneUsage, .keyboardMetrics, .sleepSession, .accelerometer, .ppg, .wristTemperature:
            return try summaryObservation(record, rawURL: rawURL, context: context)
        case .raw:
            throw SensorKitRecordError.sourceTypeNotAdmitted(record.sourceToken)
        }
    }

    /// The raw DocumentReference carrying the record's exact native recording; `relatedURL` is the fullUrl of the
    /// record's structured output, when it has one.
    static func buildDocument(
        _ record: SensorKitRecord,
        native: SensorKitNativeRecording,
        relatedURL: String?,
        context: ContentContext
    ) throws -> DocumentReference {
        let entry = try catalogEntry(sourceToken: record.sourceToken)
        let sourcePeriod = try record.rawEffectivePeriod.map {
            try period(start: $0.start, end: $0.end, timeZone: context.sourceTimeZone)
        }
        let related = relatedURL.map { [reference($0)] }
        var document = DocumentReference(
            content: [DocumentReferenceContent(
                attachment: try attachment(native),
                format: try recordingFormat(native.format, entry: entry)
            )],
            context: sourcePeriod == nil && related == nil ? nil : DocumentReferenceContext(period: sourcePeriod, related: related),
            meta: Meta(profile: entry.rawProfiles.map(profile)),
            status: FHIRPrimitive(.current),
            type: CodeableConcept(coding: [Coding(
                code: entry.sourceTypeCode.asFHIRStringPrimitive(),
                system: SensorKitContract.sourceTypeCodeSystem.asFHIRURIPrimitive()
            )])
        )
        document.extension = [sourceTypeExtension(entry.sourceTypeCode)]
        return document
    }

    private static func rotationRateObservation(
        _ record: SensorKitRotationRateRecord,
        context: ContentContext
    ) throws -> Observation {
        guard record.samples.count >= 2 else {
            throw SensorKitRecordError.emptySamples
        }
        let instants = try record.samples.enumerated().map { index, sample in
            for (field, value) in [("x", sample.x), ("y", sample.y), ("z", sample.z)] where !value.isFinite {
                throw SensorKitRecordError.nonFiniteValue(field: field, index: index)
            }
            return try epochDecimal(sample.timestamp, field: "timestamp", index: index)
        }
        let periodSeconds = instants[1] - instants[0]
        guard periodSeconds > 0 else {
            throw SensorKitRecordError.nonUniformTiming(index: 1)
        }
        for index in instants.indices.dropFirst(2)
        where instants[index] != instants[0] + Decimal(index) * periodSeconds {
            throw SensorKitRecordError.nonUniformTiming(index: index)
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.rotationRate")
        var observation = baseObservation(
            code: Coding(
                code: entry.sourceTypeCode.asFHIRStringPrimitive(),
                display: "Rotation rate".asFHIRStringPrimitive(),
                system: SensorKitContract.sourceTypeCodeSystem.asFHIRURIPrimitive()
            ),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode
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
        _ record: SensorKitECGRecord,
        rawURL: String,
        context: ContentContext
    ) throws -> Observation {
        let validated = try validateECG(record)
        let entry = try catalogEntry(sourceToken: "SRSensor.electrocardiogram")
        var observation = baseObservation(
            code: Coding(
                code: "11524-6".asFHIRStringPrimitive(),
                display: "EKG study".asFHIRStringPrimitive(),
                system: "http://loinc.org".asFHIRURIPrimitive()
            ),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode
        )
        observation.method = CodeableConcept(coding: [Coding(
            code: record.guidance.rawValue.asFHIRStringPrimitive(),
            display: (record.guidance == .guided ? "Guided" : "Unguided").asFHIRStringPrimitive(),
            system: SensorKitContract.valueCodeSystem.asFHIRURIPrimitive()
        )])
        observation.effective = .period(Period(
            end: FHIRPrimitive(try exactDateTime(
                validated.firstSampleDate,
                offsetSeconds: validated.lastOffsetSeconds,
                timeZone: context.sourceTimeZone
            )),
            start: FHIRPrimitive(try exactDateTime(
                validated.firstSampleDate,
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
            system: SensorKitContract.ecgLeadCodeSystem.asFHIRURIPrimitive()
        )]
        if record.lead == .leftArmMinusRightArm {
            leadCodings.append(Coding(
                code: "131329".asFHIRStringPrimitive(),
                display: "MDC_ECG_ELEC_POTL_I".asFHIRStringPrimitive(),
                system: Canonicals.mdc
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
        _ record: SensorKitOnWristRecord,
        context: ContentContext
    ) throws -> Observation {
        guard record.currentStateStart <= record.timestamp else {
            throw SensorKitRecordError.invalidCurrentStatePeriod
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.onWristState")
        var observation = baseObservation(
            code: conceptCoding("on-wrist-state", "On-wrist state"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode
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
        _ record: SensorKitDeviceUsageRecord,
        rawURL: String,
        context: ContentContext
    ) throws -> Observation {
        guard record.durationSeconds.isFinite, record.durationSeconds > 0,
              record.totalUnlockDurationSeconds.isFinite,
              record.totalUnlockDurationSeconds >= 0,
              record.totalUnlockDurationSeconds <= record.durationSeconds else {
            throw SensorKitRecordError.invalidDeviceUsagePeriod
        }
        for (field, value) in [
            ("totalScreenWakes", record.totalScreenWakes),
            ("totalUnlocks", record.totalUnlocks)
        ] where value < 0 || Int32(exactly: value) == nil {
            throw SensorKitRecordError.invalidDeviceUsageCount(field: field, value: value)
        }
        let duration = try decimal(record.durationSeconds, field: "duration", index: nil)
        let entry = try catalogEntry(sourceToken: "SRSensor.deviceUsageReport")
        var observation = baseObservation(
            code: conceptCoding("device-usage-summary", "Device usage summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode
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
        _ record: SensorKitVisitRecord,
        context: ContentContext
    ) throws -> Observation {
        guard record.arrivalWindow.start <= record.arrivalWindow.end,
              record.departureWindow.start <= record.departureWindow.end,
              record.arrivalWindow.start <= record.departureWindow.end,
              record.distanceFromHomeMeters.isFinite,
              record.distanceFromHomeMeters >= 0 else {
            throw SensorKitRecordError.invalidVisitPeriod
        }
        let entry = try catalogEntry(sourceToken: "SRSensor.visits")
        var observation = baseObservation(
            code: conceptCoding("visit-summary", "Visit summary"),
            profiles: entry.structuredProfiles,
            sourceTypeCode: entry.sourceTypeCode
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
        if let locationID = record.locationID {
            observation.focus = [Reference(
                identifier: Identifier(
                    system: FHIRPrimitive(FHIRURI(
                        stringLiteral: context.visitLocationIdentifierSystem.rawValue
                    )),
                    value: locationID.uuidString.lowercased().asFHIRStringPrimitive()
                ),
                type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.location.rawValue))
            )]
        }
        return observation
    }
}
