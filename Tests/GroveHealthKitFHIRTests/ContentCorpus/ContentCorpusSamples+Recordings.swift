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
@testable import GroveHealthKitFHIR
import HealthKit


/// The records that convert through their own entry points: an ECG with its voltages and symptoms, a heartbeat
/// series with its beats, and a workout route with its fixes.
extension ContentCorpusSamples {
    /// The ECG record the record entry point takes; each symptom spans the ECG's interval in the default zone.
    static func electrocardiogram(_ source: ContentCorpusSource, reading: ContentCorpusElectrocardiogram) throws -> HealthKitFHIRExporter.Record {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let ecg = try StoredSampleFixtures.electrocardiogram(
            facts: facts(source),
            reading: StoredElectrocardiogram.Reading(
                classification: try rawEnumeration(reading.classification, HKElectrocardiogram.Classification.init(rawValue:)),
                symptomsStatus: try rawEnumeration(reading.symptomsStatus, HKElectrocardiogram.SymptomsStatus.init(rawValue:)),
                numberOfVoltageMeasurements: reading.reportedCount,
                averageHeartRate: reading.averageHeartRate.map { HKQuantity(unit: beatsPerMinute, doubleValue: $0) },
                samplingFrequency: reading.samplingFrequency.map { HKQuantity(unit: .hertz(), doubleValue: $0) }
            )
        )
        var symptomSource = source
        symptomSource.device = nil
        symptomSource.writer = .unattributed
        symptomSource.metadata = [HKMetadataKeyTimeZone: .string(GoldenFixtures.timeZone)]
        return .electrocardiogram(
            ecg,
            voltages: try reading.voltages.map { voltage in
                try StoredSampleFixtures.voltageMeasurement(offset: voltage.offset, millivolts: voltage.millivolts)
            },
            symptoms: try reading.symptoms.map { symptom in
                try StoredSampleFixtures.categorySample(
                    try categoryType(symptom.type),
                    value: symptom.value,
                    facts: facts(symptomSource, uuid: GoldenFixtures.uuid(symptom.ordinal))
                )
            }
        )
    }

    /// The heartbeat series record the record entry point takes.
    static func heartbeatSeries(_ source: ContentCorpusSource, beats: [ContentCorpusBeat]) throws -> HealthKitFHIRExporter.Record {
        .heartbeatSeries(
            try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), facts: facts(source)),
            beats: beats.map(\.heartbeat)
        )
    }

    /// The workout route record the record entry point takes.
    static func workoutRoute(_ source: ContentCorpusSource, locations: [ContentCorpusLocation]) throws -> HealthKitFHIRExporter.Record {
        let start = Date(timeIntervalSince1970: source.start)
        return .workoutRoute(
            try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), facts: facts(source)),
            locations: locations.map { $0.location(after: start) }
        )
    }

    /// An imported enumeration's case for any raw value, known to this SDK or not.
    private static func rawEnumeration<Value>(_ raw: Int, _ make: (Int) -> Value?) throws -> Value {
        guard let value = make(raw) else {
            throw RebuildError.unstatable("raw value \(raw)")
        }
        return value
    }
}


extension ContentCorpusBeat {
    /// The beat as the converter's record states it.
    var heartbeat: HealthKitFHIRExporter.Record.Heartbeat {
        HealthKitFHIRExporter.Record.Heartbeat(timeSinceSeriesStart: offset, precededByGap: gap)
    }
}


extension ContentCorpusLocation {
    /// The fix as CoreLocation reports it, `offset` seconds after `start`.
    func location(after start: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speed,
            speedAccuracy: speedAccuracy,
            timestamp: start.addingTimeInterval(offset)
        )
    }
}

#endif
