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
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4


enum GoldenCaseError: Error {
    case unexpectedCompanions(Int)
    case routeOmitted
    case notExported(String)
}


/// The ECG, recording-document and retraction shapes the goldens pin.
extension GoldenCase {
    /// Sequences 60-79: graphs whose source has no public initializer, built on stored-sample fixtures.
    ///
    /// The ECG goes through `HealthKitConverter.convertECG(_:evidence:symptoms:context:symptomContexts:)`, the
    /// internal seam that takes the ECG's evidence as given; the envelope sample is a real `HKElectrocardiogram`
    /// nonetheless. These goldens predate `StoredSampleFixtures.electrocardiogram(facts:reading:)`, which states a
    /// whole reading, so the content corpus converts its ECGs through the public record entry point instead. Both
    /// state the same reading (`ContentCorpusGrid.electrocardiogramReading`), as the series and route state the
    /// corpus's beats and fixes.
    static let documents: [GoldenCase] = [
        GoldenCase("electrocardiogram", sequence: 60) { sequence in
            try GoldenOutput(primaryOf: electrocardiogram(uuid: 60, sequence: sequence, symptom: nil))
        },
        GoldenCase("electrocardiogram-with-symptom", sequence: 61) { sequence in
            try GoldenOutput(primaryOf: electrocardiogram(uuid: 61, sequence: sequence, symptom: GoldenFixtures.uuid(0x61)), companions: 1)
        },
        GoldenCase("electrocardiogram-symptom-companion", sequence: 61) { sequence in
            let companions = try electrocardiogram(uuid: 61, sequence: sequence, symptom: GoldenFixtures.uuid(0x61)).companions
            guard companions.count == 1, let companion = companions.first else {
                throw GoldenCaseError.unexpectedCompanions(companions.count)
            }
            return GoldenOutput(companion)
        },
        GoldenCase("heartbeat-series", sequence: 62) { sequence in
            let series = try StoredSampleFixtures.seriesSample(
                HKHeartbeatSeriesSample.self,
                sampleType: HKSeriesType.heartbeat(),
                facts: seriesFacts(uuid: 62, duration: 2)
            )
            let record = HealthKitHeartbeatSeriesRecord(series: series, heartbeats: ContentCorpusGrid.heartbeats.map(\.heartbeat))
            return try GoldenOutput(primaryOf: HealthKitConverter().convert(record, context: GoldenFixtures.context(sequence: sequence)))
        },
        GoldenCase("workout-route", sequence: 63) { sequence in
            let route = try StoredSampleFixtures.seriesSample(
                HKWorkoutRoute.self,
                sampleType: HKSeriesType.workoutRoute(),
                facts: seriesFacts(uuid: 63, duration: 1)
            )
            var inputs = GoldenFixtures.Inputs()
            inputs.options.routeDisclosure = .authorized
            let record = HealthKitWorkoutRouteRecord(route: route, locations: routeLocations)
            guard let conversion = try HealthKitConverter().convert(record, context: GoldenFixtures.context(sequence: sequence, inputs)) else {
                throw GoldenCaseError.routeOmitted
            }
            return try GoldenOutput(primaryOf: conversion)
        }
    ] + clinicalDocuments

    /// Sequences 80-99: retractions of deleted records.
    static let retractions: [GoldenCase] = [
        GoldenCase("retraction-heart-rate", sequence: 80) { sequence in
            GoldenOutput(try HealthKitConverter().retraction(
                for: HealthKitSourceRecord(uuid: GoldenFixtures.uuid(80), type: .heartRate),
                context: GoldenFixtures.context(sequence: sequence),
                occurred: .instant(GoldenFixtures.conversionInstant)
            ))
        },
        GoldenCase("retraction-heart-rate-native-identifier", sequence: 81) { sequence in
            var inputs = GoldenFixtures.Inputs()
            inputs.options.nativeIdentifierDisclosure = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            return GoldenOutput(try HealthKitConverter().retraction(
                for: HealthKitSourceRecord(uuid: GoldenFixtures.uuid(81), type: .heartRate),
                context: GoldenFixtures.context(sequence: sequence, inputs),
                occurred: .period(start: GoldenFixtures.sampleStart, end: GoldenFixtures.conversionInstant)
            ))
        },
        GoldenCase("retraction-electrocardiogram", sequence: 82) { sequence in
            GoldenOutput(try HealthKitConverter().retraction(
                for: HealthKitSourceRecord(uuid: GoldenFixtures.uuid(82), type: .electrocardiogram),
                context: GoldenFixtures.context(sequence: sequence),
                occurred: .instant(GoldenFixtures.conversionInstant)
            ))
        },
        GoldenCase("retraction-blood-pressure", sequence: 83) { sequence in
            GoldenOutput(try HealthKitConverter().retraction(
                for: HealthKitSourceRecord(uuid: GoldenFixtures.uuid(83), type: .bloodPressure),
                context: GoldenFixtures.context(sequence: sequence),
                occurred: .period(start: nil, end: GoldenFixtures.conversionInstant)
            ))
        },
        GoldenCase("retraction-workout", sequence: 84) { sequence in
            GoldenOutput(try HealthKitConverter().retraction(
                for: HealthKitSourceRecord(uuid: GoldenFixtures.uuid(84), type: .workout),
                context: GoldenFixtures.context(sequence: sequence),
                occurred: .instant(GoldenFixtures.conversionInstant)
            ))
        }
    ]

    #if os(watchOS)
    static let clinicalDocuments: [GoldenCase] = []
    #else
    /// `HKCDADocumentSample` has a public initializer, but no watchOS.
    static let clinicalDocuments: [GoldenCase] = [
        GoldenCase("clinical-document", sequence: 64) { sequence in
            let document = try HKCDADocumentSample(
                data: Data(clinicalDocumentXML.utf8),
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart.addingTimeInterval(1),
                metadata: GoldenFixtures.timeZoneMetadata
            )
            return try GoldenFixtures.convert(StoredSampleFixtures.stored(document, uuid: GoldenFixtures.uuid(64)), sequence: sequence)
        }
    ]
    #endif

    /// The corpus's two fixes one second apart; the second one reports no vertical accuracy, course or speed.
    static let routeLocations = ContentCorpusGrid.routeLocations.map { $0.location(after: GoldenFixtures.sampleStart) }

    static let clinicalDocumentXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ClinicalDocument xmlns="urn:hl7-org:v3">
          <typeId root="2.16.840.1.113883.1.3" extension="POCD_HD000040"/>
          <id root="2.16.840.1.113883.19.5" extension="grove-golden-1"/>
          <code code="34133-9" codeSystem="2.16.840.1.113883.6.1" displayName="Summarization of Episode Note"/>
          <title>Grove Golden Summary</title>
          <effectiveTime value="20260817153000"/>
          <confidentialityCode code="N" codeSystem="2.16.840.1.113883.5.25"/>
          <languageCode code="en-US"/>
          <recordTarget><patientRole><id root="2.16.840.1.113883.19.5" extension="p-1"/>\
        <patient><name><given>Example</given><family>Participant</family></name></patient></patientRole></recordTarget>
          <author><time value="20260817153000"/><assignedAuthor><id root="2.16.840.1.113883.19.5" extension="a-1"/>\
        <assignedPerson><name><given>Ada</given><family>Clinician</family></name></assignedPerson></assignedAuthor></author>
          <custodian><assignedCustodian><representedCustodianOrganization>\
        <id root="2.16.840.1.113883.19.5" extension="c-1"/><name>Example Hospital</name>\
        </representedCustodianOrganization></assignedCustodian></custodian>
          <component><structuredBody><component><section><title>Notes</title><text>Example.</text></section>\
        </component></structuredBody></component>
        </ClinicalDocument>
        """

    /// The sinus-rhythm ECG the conformance fixtures use, converted with or without one correlated symptom.
    ///
    /// The symptom's own event takes `sequence + 100`, the only second sequence any case states.
    static func electrocardiogram(uuid ordinal: UInt8, sequence: UInt64, symptom: UUID?) throws -> HealthKitConversionSet {
        let (ecg, evidence) = try electrocardiogramEvidence(uuid: ordinal, symptomsPresent: symptom != nil)
        var symptoms: [HKCategorySample] = []
        var symptomContexts: [HealthKitConversionContext] = []
        if let symptom {
            symptoms = [try Self.symptom(uuid: symptom)]
            symptomContexts = [try GoldenFixtures.context(sequence: sequence + 100)]
        }
        return try HealthKitConverter.convertECG(
            ecg,
            evidence: evidence,
            symptoms: symptoms,
            context: GoldenFixtures.context(sequence: sequence),
            symptomContexts: symptomContexts
        )
    }

    /// The sinus-rhythm ECG sample and the validated evidence its voltages would yield, with symptoms present or none,
    /// and the average heart rate the ECG states, if any. The sample's metadata states the golden time zone unless
    /// `timeZoned` is false; the evidence reads it from there, as the public path does.
    static func electrocardiogramEvidence(
        uuid ordinal: UInt8,
        symptomsPresent: Bool,
        averageHeartRate: Double? = ContentCorpusGrid.electrocardiogramReading.averageHeartRate,
        timeZoned: Bool = true
    ) throws -> (sample: HKElectrocardiogram, evidence: HealthKitECGEvidence) {
        var facts = seriesFacts(uuid: ordinal, duration: 30)
        facts.metadata = timeZoned ? facts.metadata : [:]
        let ecg = try StoredSampleFixtures.seriesSample(HKElectrocardiogram.self, sampleType: HKObjectType.electrocardiogramType(), facts: facts)
        let reading = ContentCorpusGrid.electrocardiogramReading
        let source = HealthKitECGSourceEvidence(
            sourceTypeIdentifier: HealthKitContract.electrocardiogramSourceTypeIdentifier,
            startDate: GoldenFixtures.sampleStart,
            endDate: GoldenFixtures.sampleStart.addingTimeInterval(30),
            timeZone: try HealthKitConverter.healthKitTimeZone(for: ecg),
            classification: .sinusRhythm,
            symptomsStatus: symptomsPresent ? .present : .none,
            numberOfVoltageMeasurements: reading.reportedCount,
            averageHeartRate: averageHeartRate,
            samplingFrequency: reading.samplingFrequency,
            algorithmVersion: HKAppleECGAlgorithmVersion.version2.rawValue
        )
        let waveform = try HealthKitECGEvidenceValidator.validateWaveform(
            reportedCount: source.numberOfVoltageMeasurements,
            samplingFrequencyHertz: source.samplingFrequency,
            points: reading.voltages.map { HealthKitECGVoltagePoint(timeSinceSampleStart: $0.offset, millivolts: $0.millivolts ?? .nan) }
        )
        return (ecg, HealthKitECGEvidence(source: source, waveform: waveform))
    }

    /// A symptom recorded by the watch and written by the foreign application; by default mild chest tightness.
    static func symptom(
        uuid: UUID,
        type: HKCategoryTypeIdentifier = .chestTightnessOrPain,
        value: Int = HKCategoryValueSeverity.mild.rawValue
    ) throws -> HKCategorySample {
        let sample = HKCategorySample(
            type: HKCategoryType(type),
            value: value,
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(30),
            device: GoldenFixtures.watch,
            metadata: GoldenFixtures.timeZoneMetadata
        )
        return try StoredSampleFixtures.stored(sample, uuid: uuid, writer: GoldenFixtures.foreignWriter)
    }

    /// A series recorded by the watch, written by the foreign application.
    static func seriesFacts(uuid ordinal: UInt8, duration: TimeInterval) -> StoredSampleFixtures.SampleFacts {
        StoredSampleFixtures.SampleFacts(
            uuid: GoldenFixtures.uuid(ordinal),
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart.addingTimeInterval(duration),
            device: GoldenFixtures.watch,
            metadata: GoldenFixtures.timeZoneMetadata,
            writer: GoldenFixtures.foreignWriter
        )
    }
}

#endif
