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


/// The clinical samples, which watchOS does not have.
enum ContentCorpusClinicalSamples {
    #if os(watchOS)
    static func sample(_ record: ContentCorpusRecord, shape: StoredSampleFixtures.SeriesShape) throws -> HKSample {
        throw ContentCorpusSamples.RebuildError.unknownClass("HKClinicalRecord")
    }
    #else
    static func sample(_ record: ContentCorpusRecord, shape: StoredSampleFixtures.SeriesShape) throws -> HKSample {
        switch record {
        case let .cdaDocument(title, document):
            return try cdaDocument(title: title, document: document, shape: shape)
        case let .clinicalRecord(type, fhirVersion, resource):
            return try clinicalRecord(type: type, fhirVersion: fhirVersion, resource: resource, shape: shape)
        default:
            throw ContentCorpusSamples.RebuildError.notASample
        }
    }

    /// A CDA sample as an `HKDocumentQuery` returns it, with its document data, or without when `document` is nil.
    private static func cdaDocument(title: String, document: String?, shape: StoredSampleFixtures.SeriesShape) throws -> HKSample {
        guard let documentType = HKObjectType.documentType(forIdentifier: .CDA) else {
            throw ContentCorpusSamples.RebuildError.unknownType(HKDocumentTypeIdentifier.CDA.rawValue)
        }
        let sample = try StoredSampleFixtures.seriesSample(HKCDADocumentSample.self, sampleType: documentType, shape: shape)
        guard let document else {
            return sample
        }
        let content = try StoredSampleFixtures.allocate(HKCDADocument.self)
        try StoredSampleFixtures.write(Data(document.utf8), to: "internalDocumentData", of: content)
        try StoredSampleFixtures.write(title, to: "title", of: content)
        try StoredSampleFixtures.write(content, to: "document", of: sample)
        guard sample.document?.documentData == Data(document.utf8), sample.document?.title == title else {
            throw ContentCorpusSamples.RebuildError.notHonored("CDA document")
        }
        return sample
    }

    /// A clinical record carrying `resource` under `fhirVersion`, or no FHIR resource at all when it is nil.
    private static func clinicalRecord(
        type: String,
        fhirVersion: String,
        resource: String?,
        shape: StoredSampleFixtures.SeriesShape
    ) throws -> HKSample {
        guard let clinicalType = HKObjectType.clinicalType(forIdentifier: HKClinicalTypeIdentifier(rawValue: type)) else {
            throw ContentCorpusSamples.RebuildError.unknownType(type)
        }
        let record = try StoredSampleFixtures.seriesSample(HKClinicalRecord.self, sampleType: clinicalType, shape: shape)
        guard let resource else {
            return record
        }
        let content = try StoredSampleFixtures.allocate(HKFHIRResource.self)
        try StoredSampleFixtures.write(Data(resource.utf8), to: "data", of: content)
        try StoredSampleFixtures.write(try HKFHIRVersion(fromVersionString: fhirVersion), to: "FHIRVersion", of: content)
        try StoredSampleFixtures.write(content, to: "FHIRResource", of: record)
        guard record.fhirResource?.data == Data(resource.utf8) else {
            throw ContentCorpusSamples.RebuildError.notHonored("FHIR resource")
        }
        return record
    }
    #endif
}


extension ContentCorpusSamples {
    /// A workout, State of Mind or scored assessment stating exactly the vector's payload.
    static func reflection(_ record: ContentCorpusRecord, shape: StoredSampleFixtures.SeriesShape) throws -> HKSample {
        switch record {
        case let .workout(activity, duration, statistics):
            try workout(activity: activity, duration: duration, statistics: statistics, shape: shape)
        case let .stateOfMind(kind, valence, labels, associations):
            try stateOfMind(kind: kind, valence: valence, labels: labels, associations: associations, shape: shape)
        case let .assessment(type, score):
            try assessment(type: type, score: score, shape: shape)
        default:
            throw RebuildError.notASample
        }
    }

    /// The ECG record the record entry point takes; each symptom carries the ECG's interval and the default zone.
    static func electrocardiogram(_ source: ContentCorpusSource, reading: ContentCorpusElectrocardiogram) throws -> HealthKitECGRecord {
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        let ecg = try StoredSampleFixtures.electrocardiogram(
            shape: shape(source),
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
        return HealthKitECGRecord(
            electrocardiogram: ecg,
            voltageMeasurements: try reading.voltages.map { voltage in
                try StoredSampleFixtures.voltageMeasurement(offset: voltage.offset, millivolts: voltage.millivolts)
            },
            correlatedSymptoms: try reading.symptoms.map { symptom in
                try category(type: symptom.type, value: symptom.value, shape: shape(symptomSource, uuid: GoldenFixtures.uuid(symptom.ordinal)))
            }
        )
    }

    static func heartbeatSeries(_ source: ContentCorpusSource, beats: [ContentCorpusBeat]) throws -> HealthKitHeartbeatSeriesRecord {
        HealthKitHeartbeatSeriesRecord(
            series: try StoredSampleFixtures.seriesSample(HKHeartbeatSeriesSample.self, sampleType: HKSeriesType.heartbeat(), shape: shape(source)),
            heartbeats: beats.map { HealthKitHeartbeat(timeSinceSeriesStart: $0.offset, precededByGap: $0.gap) }
        )
    }

    static func workoutRoute(_ source: ContentCorpusSource, locations: [ContentCorpusLocation]) throws -> HealthKitWorkoutRouteRecord {
        let start = Date(timeIntervalSince1970: source.start)
        return HealthKitWorkoutRouteRecord(
            route: try StoredSampleFixtures.seriesSample(HKWorkoutRoute.self, sampleType: HKSeriesType.workoutRoute(), shape: shape(source)),
            locations: locations.map { fix in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
                    altitude: fix.altitude,
                    horizontalAccuracy: fix.horizontalAccuracy,
                    verticalAccuracy: fix.verticalAccuracy,
                    course: fix.course,
                    courseAccuracy: fix.courseAccuracy,
                    speed: fix.speed,
                    speedAccuracy: fix.speedAccuracy,
                    timestamp: start.addingTimeInterval(fix.offset)
                )
            }
        )
    }

    /// An imported enumeration's case for any raw value, known to this SDK or not.
    private static func rawEnumeration<Value>(_ raw: Int, _ make: (Int) -> Value?) throws -> Value {
        guard let value = make(raw) else {
            throw RebuildError.notHonored("raw value \(raw)")
        }
        return value
    }

    /// A workout of any activity raw value, duration and statistics; HealthKit computes statistics only while
    /// recording one, so they are written into its primary activity.
    private static func workout(
        activity: UInt,
        duration: Double,
        statistics: [ContentCorpusStatistic],
        shape: StoredSampleFixtures.SeriesShape
    ) throws -> HKWorkout {
        let workout = HKWorkout(activityType: .running, start: GoldenFixtures.sampleStart, end: GoldenFixtures.sampleStart.addingTimeInterval(60))
        try StoredSampleFixtures.write(NSNumber(value: activity), to: "workoutActivityType", of: workout)
        try StoredSampleFixtures.write(NSNumber(value: duration), to: "duration", of: workout)
        guard let primary = workout.value(forKey: "primaryActivity") as? NSObject,
              let byType = primary.value(forKey: "statisticsPerType") as? NSMutableDictionary else {
            throw RebuildError.notHonored("workout statistics")
        }
        for statistic in statistics {
            let quantityType = try workoutStatisticType(statistic.type)
            byType[quantityType] = try workoutStatistic(statistic, type: quantityType)
        }
        guard workout.workoutActivityType.rawValue == activity, workout.duration.bitPattern == duration.bitPattern,
              workout.allStatistics.count == statistics.count else {
            throw RebuildError.notHonored("workout activity, duration or statistics")
        }
        return try StoredSampleFixtures.restated(workout, shape: shape)
    }

    private static func workoutStatisticType(_ type: String) throws -> HKQuantityType {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: type)) else {
            throw RebuildError.unknownType(type)
        }
        return quantityType
    }

    /// One statistics object with only the readings the vector states.
    private static func workoutStatistic(_ statistic: ContentCorpusStatistic, type: HKQuantityType) throws -> NSObject {
        let unit = HKUnit(from: statistic.unit)
        guard type.is(compatibleWith: unit) else {
            throw RebuildError.incompatibleUnit(type: statistic.type, unit: statistic.unit)
        }
        let object = try StoredSampleFixtures.allocate(HKStatistics.self)
        try StoredSampleFixtures.write(type, to: "dataType", of: object)
        let readings: [(key: String, value: Double?)] = [
            ("sumQuantity", statistic.sum), ("averageQuantity", statistic.average),
            ("minimumQuantity", statistic.minimum), ("maximumQuantity", statistic.maximum)
        ]
        for reading in readings {
            try StoredSampleFixtures.write(reading.value.map { HKQuantity(unit: unit, doubleValue: $0) }, to: reading.key, of: object)
        }
        return object
    }

    /// A reflection of any kind and labels, which HealthKit refuses at creation unless it knows them.
    private static func stateOfMind(
        kind: Int,
        valence: Double,
        labels: [Int],
        associations: [Int],
        shape: StoredSampleFixtures.SeriesShape
    ) throws -> HKStateOfMind {
        // HealthKit classifies the valence when it is read and traps outside -1...1, so no vector states one.
        guard (-1...1).contains(valence) else {
            throw RebuildError.notHonored("valence \(valence)")
        }
        let reflection = HKStateOfMind(date: GoldenFixtures.sampleStart, kind: .momentaryEmotion, valence: 0, labels: [], associations: [])
        try StoredSampleFixtures.write(NSNumber(value: kind), to: "kind", of: reflection)
        try StoredSampleFixtures.write(NSNumber(value: valence), to: "valence", of: reflection)
        try StoredSampleFixtures.write(labels.map { NSNumber(value: $0) }, to: "labels", of: reflection)
        try StoredSampleFixtures.write(associations.map { NSNumber(value: $0) }, to: "associations", of: reflection)
        guard reflection.kind.rawValue == kind, reflection.valence == valence,
              reflection.labels.map(\.rawValue) == labels, reflection.associations.map(\.rawValue) == associations else {
            throw RebuildError.notHonored("State of Mind")
        }
        return try StoredSampleFixtures.restated(reflection, shape: shape)
    }

    /// A GAD-7 or PHQ-9 assessment stating any score.
    private static func assessment(type: String, score: Int, shape: StoredSampleFixtures.SeriesShape) throws -> HKScoredAssessment {
        let assessment: HKScoredAssessment = switch type {
        case HKScoredAssessmentTypeIdentifier.GAD7.rawValue:
            HKGAD7Assessment(date: GoldenFixtures.sampleStart, answers: Array(repeating: .notAtAll, count: 7))
        case HKScoredAssessmentTypeIdentifier.PHQ9.rawValue:
            HKPHQ9Assessment(date: GoldenFixtures.sampleStart, answers: Array(repeating: .notAtAll, count: 9))
        default:
            throw RebuildError.unknownType(type)
        }
        try StoredSampleFixtures.write(NSNumber(value: score), to: "score", of: assessment)
        guard assessment.score == score else {
            throw RebuildError.notHonored("assessment score")
        }
        return try StoredSampleFixtures.restated(assessment, shape: shape)
    }
}

#endif
