//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
import Foundation
import GroveFHIRContract
public import HealthKit
import ModelsR4


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    /// Converts an already-fetched ECG and every correlated symptom as independently exchangeable
    /// source events.
    ///
    /// The context provider is intentionally required for every source sample. Reusing the ECG's
    /// event context for a symptom would collapse two source-record revisions into one event, while
    /// omitting symptom conversions would leave identifier-only `hasMember` references dangling.
    public func convert(
        _ record: HealthKitECGRecord,
        contextForSample: (HKSample) throws -> HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        do {
            let symptoms = try Self.validatedSymptomSamples(
                record.correlatedSymptoms,
                status: record.electrocardiogram.symptomsStatus
            )
            let symptomConversions = try symptoms.map { symptom in
                try Self.convertSample(symptom, context: contextForSample(symptom))
            }
            return try Self.convertECG(
                HealthKitECGRecord(
                    electrocardiogram: record.electrocardiogram,
                    voltageMeasurements: record.voltageMeasurements,
                    correlatedSymptoms: symptoms
                ),
                context: try contextForSample(record.electrocardiogram),
                symptomConversions: symptomConversions
            )
        } catch {
            throw HealthKitConversionError(conversionFailure: error)
        }
    }

    /// Convenience form that keeps each already-fetched evidence family explicit.
    public func convert(
        _ electrocardiogram: HKElectrocardiogram,
        voltageMeasurements: [HKElectrocardiogram.VoltageMeasurement],
        correlatedSymptoms: [HKCategorySample] = [],
        contextForSample: (HKSample) throws -> HealthKitConversionContext
    ) throws(HealthKitConversionError) -> HealthKitConversionSet {
        try convert(
            HealthKitECGRecord(
                electrocardiogram: electrocardiogram,
                voltageMeasurements: voltageMeasurements,
                correlatedSymptoms: correlatedSymptoms
            ),
            contextForSample: contextForSample
        )
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitConverter {
    static func averageHeartRateObservation(
        value: Double,
        identity: BusinessIdentifier,
        effective: Period,
        input: HealthKitECGObservationInput,
        envelope: GraphEnvelope
    ) throws -> Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(
                    code: "8867-4",
                    display: "Heart rate",
                    system: "http://loinc.org"
                )
            ]),
            status: FHIRPrimitive(.final)
        )
        observation.category = [
            CodeableConcept(coding: [
                Coding(
                    code: "vital-signs",
                    display: "Vital Signs",
                    system: "http://terminology.hl7.org/CodeSystem/observation-category"
                )
            ])
        ]
        applySourceTypeLineage(input.source.sourceTypeIdentifier, to: &observation)
        observation.meta = Meta(profile: [
            Profile.groveMobileHeartRate,
            Profile.healthkitEcgAverageHeartRateObservation
        ])
        observation.identifier = [
            envelope.sourceRecord.fhirIdentifier,
            identity.fhirIdentifier
        ]
        observation.subject = input.context.subject
        observation.effective = .period(effective)
        observation.value = .quantity(try decimalQuantity(
            value,
            code: "/min",
            display: "beats/minute"
        ))
        observation.derivedFrom = [
            Reference(reference: envelope.primaryURL.asFHIRStringPrimitive())
        ]
        applyGraphContext(
            to: &observation,
            context: input.context,
            graphContext: .init(
                recordingDeviceURL: envelope.recordingDeviceURL,
                converterURL: envelope.converterURL
            ),
            wasUserEntered: input.source.wasUserEntered
        )
        return observation
    }

    /// Constructs a FHIR dateTime from the shortest round-trip representation of
    /// Foundation's source instant, then adds an exact decimal HealthKit offset.
    /// Going through `Date.addingTimeInterval` would introduce a second binary
    /// floating-point rounding step and can make SampledData's period arithmetic
    /// fail despite a complete uniform voltage enumeration.
    static func exactHealthKitDateTime(
        _ date: Date,
        offsetSeconds: Decimal = 0,
        timeZone: TimeZone
    ) throws -> DateTime {
        let epochSeconds = date.timeIntervalSince1970
        guard epochSeconds.isFinite,
              let epochDecimal = Decimal(
                  string: String(epochSeconds),
                  locale: Locale(identifier: "en_US_POSIX")
              ) else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSourcePeriod)
        }
        let target = epochDecimal + offsetSeconds
        let approximateTarget = NSDecimalNumber(decimal: target).doubleValue
        guard approximateTarget.isFinite,
              approximateTarget >= Double(Int64.min),
              approximateTarget <= Double(Int64.max) else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSourcePeriod)
        }

        var wholeSeconds = Int64(floor(approximateTarget))
        var fractionalSecond = target - Decimal(wholeSeconds)
        if fractionalSecond < 0 {
            wholeSeconds -= 1
            fractionalSecond += 1
        } else if fractionalSecond >= 1 {
            wholeSeconds += 1
            fractionalSecond -= 1
        }

        let wholeSecondDate = Date(timeIntervalSince1970: TimeInterval(wholeSeconds))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: wholeSecondDate
        )
        guard let year = components.year,
              let month = components.month.flatMap(UInt8.init(exactly:)),
              let day = components.day.flatMap(UInt8.init(exactly:)),
              let hour = components.hour.flatMap(UInt8.init(exactly:)),
              let minute = components.minute.flatMap(UInt8.init(exactly:)),
              let second = components.second else {
            throw HealthKitConversionError.invalidECGEvidence(.invalidSourcePeriod)
        }
        return DateTime(
            date: FHIRDate(year: year, month: month, day: day),
            time: FHIRTime(
                hour: hour,
                minute: minute,
                second: Decimal(second) + fractionalSecond
            ),
            timezone: timeZone
        )
    }
}

#endif
