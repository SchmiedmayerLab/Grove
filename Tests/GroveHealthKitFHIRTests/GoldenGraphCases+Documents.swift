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
    case notExported(String)
}


/// The ECG, recording-document and retraction shapes the goldens pin.
extension GoldenCase {
    /// Sequences 60-79: graphs whose source has no public initializer, built on stored-sample fixtures.
    ///
    /// The ECG states the content corpus's reading (`ContentCorpusGrid.electrocardiogramReading`) through
    /// `StoredSampleFixtures.electrocardiogram(facts:reading:)` and exports with its voltages, as the series and route
    /// state the corpus's beats and fixes.
    static let documents: [GoldenCase] = [
        GoldenCase("electrocardiogram", sequence: 60) { sequence in
            try await electrocardiogram(uuid: 60, sequence: sequence, symptom: nil, index: 0)
        },
        GoldenCase("electrocardiogram-with-symptom", sequence: 61) { sequence in
            try await electrocardiogram(uuid: 61, sequence: sequence, symptom: GoldenFixtures.uuid(0x61), index: 0)
        },
        GoldenCase("electrocardiogram-symptom-companion", sequence: 61) { sequence in
            try await electrocardiogram(uuid: 61, sequence: sequence, symptom: GoldenFixtures.uuid(0x61), index: 1)
        },
        GoldenCase("heartbeat-series", sequence: 62) { sequence in
            let series = try StoredSampleFixtures.seriesSample(
                HKHeartbeatSeriesSample.self,
                sampleType: HKSeriesType.heartbeat(),
                facts: seriesFacts(uuid: 62, duration: 2)
            )
            return try await GoldenFixtures.export(.heartbeatSeries(series, beats: ContentCorpusGrid.heartbeats.map(\.heartbeat)), sequence: sequence)
        },
        GoldenCase("workout-route", sequence: 63) { sequence in
            let route = try StoredSampleFixtures.seriesSample(
                HKWorkoutRoute.self,
                sampleType: HKSeriesType.workoutRoute(),
                facts: seriesFacts(uuid: 63, duration: 1)
            )
            var inputs = ExportInputs()
            inputs.options.route = .authorized
            return try await GoldenFixtures.export(.workoutRoute(route, locations: routeLocations), sequence: sequence, inputs)
        }
    ] + clinicalDocuments

    /// Sequences 80-99: retractions of deleted records, each stating the bounds a deletion the app noted carries. (The
    /// deleted context API could state an exact deletion instant; HealthKit reports none, so the exporter states bounds.)
    static let retractions: [GoldenCase] = [
        GoldenCase("retraction-heart-rate", sequence: 80) { sequence in
            try await retraction(of: .heartRate, uuid: 80, sequence: sequence)
        },
        GoldenCase("retraction-heart-rate-native-identifier", sequence: 81) { sequence in
            var inputs = ExportInputs()
            inputs.options.nativeIdentifier = .authorized(system: GoldenFixtures.nativeIdentifierSystem)
            return try await retraction(of: .heartRate, uuid: 81, sequence: sequence, deletedAfter: GoldenFixtures.sampleStart, inputs)
        },
        GoldenCase("retraction-electrocardiogram", sequence: 82) { sequence in
            try await retraction(of: .electrocardiogram, uuid: 82, sequence: sequence)
        },
        GoldenCase("retraction-blood-pressure", sequence: 83) { sequence in
            try await retraction(of: .bloodPressure, uuid: 83, sequence: sequence)
        },
        GoldenCase("retraction-workout", sequence: 84) { sequence in
            try await retraction(of: .workout, uuid: 84, sequence: sequence)
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
            return try await GoldenFixtures.export(StoredSampleFixtures.stored(document, uuid: GoldenFixtures.uuid(64)), sequence: sequence)
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

    /// The graph at `index` of the sinus-rhythm ECG the conformance fixtures use, exported with or without one
    /// correlated symptom: the ECG's own graph first, then the symptom's.
    ///
    /// The symptom's own event takes `sequence + 100`, the only second sequence any case states.
    static func electrocardiogram(uuid ordinal: UInt8, sequence: UInt64, symptom: UUID?, index: Int) async throws -> GoldenOutput {
        let symptoms = try symptom.map { [try Self.symptom(uuid: $0)] } ?? []
        var inputs = ExportInputs()
        inputs.symptomSequences = [sequence + 100]
        let record = try ExporterFixtures.electrocardiogram(electrocardiogramRecord(uuid: ordinal, symptoms: symptoms), symptoms: symptoms)
        return try await GoldenFixtures.export(record, sequence: sequence, inputs, index: index, of: 1 + symptoms.count)
    }

    /// The retraction of the record of `type` with the `ordinal` UUID, deleted after `deletedAfter` when known and
    /// detected at the conversion instant.
    static func retraction(
        of type: HealthKitSourceType,
        uuid ordinal: UInt8,
        sequence: UInt64,
        deletedAfter: Date? = nil,
        _ inputs: ExportInputs = ExportInputs()
    ) async throws -> GoldenOutput {
        var inputs = inputs
        inputs.sequence = sequence
        let deletion = HealthKitFHIRExporter.Deletion(
            uuid: GoldenFixtures.uuid(ordinal),
            sourceType: type,
            deletedAfter: deletedAfter,
            detectedAt: GoldenFixtures.conversionInstant
        )
        let (exporter, _) = try ExporterFixtures.exporter(inputs)
        let (retractions, _) = try await ExporterFixtures.retract(exporter, [deletion])
        return try GoldenOutput(ExporterGolden.single(retractions))
    }

    /// An ECG of the corpus's reading under Apple's second algorithm version, with its voltages, recorded by the watch
    /// and written by the foreign application: sinus rhythm unless `classification` says otherwise, in the goldens' zone
    /// unless `timeZoned` is false, stating `averageHeartRate` (by default the reading's), and stating its symptoms
    /// present exactly when `symptoms` has any.
    static func electrocardiogramRecord(
        uuid ordinal: UInt8,
        symptoms: [HKCategorySample],
        classification: HKElectrocardiogram.Classification = .sinusRhythm,
        averageHeartRate: Double? = ContentCorpusGrid.electrocardiogramReading.averageHeartRate,
        timeZoned: Bool = true
    ) throws -> ECGRecording {
        let reading = ContentCorpusGrid.electrocardiogramReading
        var facts = seriesFacts(uuid: ordinal, duration: 30)
        facts.metadata = (timeZoned ? GoldenFixtures.timeZoneMetadata : [:]).merging([
            HKMetadataKeyAppleECGAlgorithmVersion: HKAppleECGAlgorithmVersion.version2.rawValue
        ]) { _, new in new }
        let ecg = try StoredSampleFixtures.electrocardiogram(facts: facts, reading: StoredElectrocardiogram.Reading(
            classification: classification,
            symptomsStatus: symptoms.isEmpty ? .none : .present,
            numberOfVoltageMeasurements: reading.reportedCount,
            averageHeartRate: averageHeartRate.map { HKQuantity(unit: GoldenFixtures.beatsPerMinute, doubleValue: $0) },
            samplingFrequency: reading.samplingFrequency.map { HKQuantity(unit: .hertz(), doubleValue: $0) }
        ))
        let voltages = try reading.voltages.map { voltage in
            try StoredSampleFixtures.voltageMeasurement(offset: voltage.offset, millivolts: voltage.millivolts)
        }
        return (ecg, voltages)
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
