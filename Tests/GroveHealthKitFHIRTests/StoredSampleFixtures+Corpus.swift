//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
import HealthKit
import ObjectiveC


/// TEST-ONLY. An `HKElectrocardiogram` that states its whole reading itself.
///
/// HealthKit keeps an ECG's voltage count and sampling frequency in a C++ reading key-value coding cannot reach,
/// and derives its classification from a private enumeration, so a stored ECG answers those five properties
/// from the reading `StoredSampleFixtures.electrocardiogram(facts:reading:)` attaches. Every other fact lives
/// where HealthKit keeps it.
final class StoredElectrocardiogram: HKElectrocardiogram, @unchecked Sendable {
    /// What an ECG reports about its recording.
    struct Reading: Sendable {
        /// The rhythm the recording was classified as, any raw value.
        var classification: HKElectrocardiogram.Classification
        /// Whether the user reported symptoms, any raw value.
        var symptomsStatus: HKElectrocardiogram.SymptomsStatus
        /// How many voltages HealthKit reports the recording to have.
        var numberOfVoltageMeasurements: Int
        /// The average heart rate over the recording.
        var averageHeartRate: HKQuantity?
        /// How often the lead was sampled.
        var samplingFrequency: HKQuantity?
    }

    /// The association key; only its address matters.
    nonisolated(unsafe) private static var readingKey: UInt8 = 0

    override var classification: Classification { reading.classification }
    override var symptomsStatus: SymptomsStatus { reading.symptomsStatus }
    override var numberOfVoltageMeasurements: Int { reading.numberOfVoltageMeasurements }
    override var averageHeartRate: HKQuantity? { reading.averageHeartRate }
    override var samplingFrequency: HKQuantity? { reading.samplingFrequency }

    /// The reading attached when the ECG was built.
    private var reading: Reading {
        guard let reading = objc_getAssociatedObject(self, &Self.readingKey) as? Reading else {
            preconditionFailure("A stored ECG states its reading when it is built")
        }
        return reading
    }

    /// Attaches the reading every overridden property answers from.
    fileprivate func state(_ reading: Reading) {
        objc_setAssociatedObject(self, &Self.readingKey, reading, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}


/// The per-class builders of the content corpus: each states one payload HealthKit would refuse at creation,
/// or keeps where only its own recording code writes it, then the sample's facts.
extension StoredSampleFixtures {
    /// One statistic of a workout: its quantity type and the readings HealthKit reported, each in `unit`; an absent
    /// reading is one HealthKit did not report.
    struct WorkoutStatistic {
        /// The statistic's quantity type.
        let type: HKQuantityType
        /// The unit every reading is stated in.
        let unit: HKUnit
        /// The cumulative reading.
        let sum: Double?
        /// The average reading.
        let average: Double?
        /// The smallest reading.
        let minimum: Double?
        /// The largest reading.
        let maximum: Double?
    }

    /// A quantity sample of any value over any interval: HealthKit validates both per type when it creates one,
    /// so this is a bare instance of the class its initializer would have chosen.
    static func quantitySample(_ type: HKQuantityType, value: Double, unit: HKUnit, facts: SampleFacts) throws -> HKQuantitySample {
        guard type.is(compatibleWith: unit) else {
            throw FixtureError.incompatibleUnit(unit: unit.unitString, type: type.identifier)
        }
        let sampleClass: HKQuantitySample.Type = type.aggregationStyle == .cumulative
            ? HKCumulativeQuantitySample.self
            : HKDiscreteQuantitySample.self
        let sample = try seriesSample(sampleClass, sampleType: type, facts: facts)
        try restate(sample, with: ["quantity": HKQuantity(unit: unit, doubleValue: value), "count": NSNumber(value: 1)])
        let stated = sample.quantity.doubleValue(for: unit)
        guard stated == value || (stated.isNaN && value.isNaN) else {
            throw FixtureError.keyNotHonored(key: "quantity", class: String(describing: sampleClass))
        }
        return sample
    }

    /// A category sample of any raw value; HealthKit refuses an unadmitted one at creation, so this is bare.
    static func categorySample(_ type: HKCategoryType, value: Int, facts: SampleFacts) throws -> HKCategorySample {
        let sample = try seriesSample(HKCategorySample.self, sampleType: type, facts: facts)
        try restate(sample, with: ["value": NSNumber(value: value)])
        guard sample.value == value else {
            throw FixtureError.keyNotHonored(key: "value", class: "HKCategorySample")
        }
        return sample
    }

    /// A correlation of exactly `objects`, which HealthKit's initializer refuses unless they are one valid set.
    ///
    /// The correlation is built around placeholder objects it admits (a blood-pressure pair, or one food entry,
    /// attributed to no writer as the initializer requires) and then states `objects` and `facts`.
    static func correlation(_ type: HKCorrelationType, objects: [HKSample], facts: SampleFacts) throws -> HKCorrelation {
        let correlation = HKCorrelation(
            type: type,
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart,
            objects: try correlationPlaceholders(for: type)
        )
        let byType = NSMutableDictionary()
        for object in objects {
            let group = byType[object.sampleType] as? NSMutableSet ?? NSMutableSet()
            group.add(object)
            byType[object.sampleType] = group
        }
        try restate(correlation, with: ["objects": byType])
        guard correlation.objects.count == objects.count else {
            throw FixtureError.keyNotHonored(key: "objects", class: "HKCorrelation")
        }
        return try restated(correlation, facts: facts)
    }

    /// A workout of any activity raw value, duration and statistics; HealthKit computes statistics only while it
    /// records a workout, so they are stated in the workout's primary activity.
    static func workout(activity: UInt, duration: TimeInterval, statistics: [WorkoutStatistic], facts: SampleFacts) throws -> HKWorkout {
        let workout = HKWorkout(activityType: .running, start: GoldenFixtures.sampleStart, end: GoldenFixtures.sampleStart.addingTimeInterval(60))
        try restate(workout, with: ["workoutActivityType": NSNumber(value: activity), "duration": NSNumber(value: duration)])
        guard let primary = try read("primaryActivity", of: workout) as? NSObject,
              let byType = try read("statisticsPerType", of: primary) as? NSMutableDictionary else {
            throw FixtureError.keyNotHonored(key: "primaryActivity/statisticsPerType", class: "HKWorkout")
        }
        for statistic in statistics {
            guard statistic.type.is(compatibleWith: statistic.unit) else {
                throw FixtureError.incompatibleUnit(unit: statistic.unit.unitString, type: statistic.type.identifier)
            }
            let quantity = { (reading: Double?) in reading.map { HKQuantity(unit: statistic.unit, doubleValue: $0) } }
            byType[statistic.type] = try instance(of: HKStatistics.self, stating: [
                "dataType": statistic.type, "sumQuantity": quantity(statistic.sum), "averageQuantity": quantity(statistic.average),
                "minimumQuantity": quantity(statistic.minimum), "maximumQuantity": quantity(statistic.maximum)
            ])
        }
        guard workout.workoutActivityType.rawValue == activity, workout.duration.bitPattern == duration.bitPattern,
              workout.allStatistics.count == statistics.count else {
            throw FixtureError.keyNotHonored(key: "workoutActivityType/duration/statisticsPerType", class: "HKWorkout")
        }
        return try restated(workout, facts: facts)
    }

    /// A reflection of any kind, valence, labels and associations; HealthKit refuses kinds and labels it does not
    /// know at creation.
    static func stateOfMind(kind: Int, valence: Double, labels: [Int], associations: [Int], facts: SampleFacts) throws -> HKStateOfMind {
        let reflection = HKStateOfMind(date: GoldenFixtures.sampleStart, kind: .momentaryEmotion, valence: 0, labels: [], associations: [])
        try restate(reflection, with: [
            "kind": NSNumber(value: kind), "valence": NSNumber(value: valence),
            "labels": labels.map { NSNumber(value: $0) }, "associations": associations.map { NSNumber(value: $0) }
        ])
        guard reflection.kind.rawValue == kind, reflection.valence == valence,
              reflection.labels.map(\.rawValue) == labels, reflection.associations.map(\.rawValue) == associations else {
            throw FixtureError.keyNotHonored(key: "kind/valence/labels/associations", class: "HKStateOfMind")
        }
        return try restated(reflection, facts: facts)
    }

    /// A GAD-7 or PHQ-9 assessment stating any score; nil for another assessment type.
    static func scoredAssessment(_ type: HKScoredAssessmentTypeIdentifier, score: Int, facts: SampleFacts) throws -> HKScoredAssessment? {
        let assessment: HKScoredAssessment
        switch type {
        case .GAD7:
            assessment = HKGAD7Assessment(date: GoldenFixtures.sampleStart, answers: Array(repeating: .notAtAll, count: 7))
        case .PHQ9:
            assessment = HKPHQ9Assessment(date: GoldenFixtures.sampleStart, answers: Array(repeating: .notAtAll, count: 9))
        default:
            return nil
        }
        try restate(assessment, with: ["score": NSNumber(value: score)])
        guard assessment.score == score else {
            throw FixtureError.keyNotHonored(key: "score", class: String(describing: Swift.type(of: assessment)))
        }
        return try restated(assessment, facts: facts)
    }

    /// An ECG carrying exactly `facts` and stating `reading` as HealthKit would report it.
    static func electrocardiogram(facts: SampleFacts, reading: StoredElectrocardiogram.Reading) throws -> HKElectrocardiogram {
        let ecg = try seriesSample(StoredElectrocardiogram.self, sampleType: HKObjectType.electrocardiogramType(), facts: facts)
        ecg.state(reading)
        return ecg
    }

    /// One voltage of an ECG's lead, or a measurement that states no lead voltage at all.
    static func voltageMeasurement(offset: TimeInterval, millivolts: Double?) throws -> HKElectrocardiogram.VoltageMeasurement {
        let measurement = try instance(of: HKElectrocardiogram.VoltageMeasurement.self, stating: [
            "timeSinceSampleStart": NSNumber(value: offset),
            "leadIVoltage": millivolts.map { HKQuantity(unit: .voltUnit(with: .milli), doubleValue: $0) }
        ])
        guard measurement.timeSinceSampleStart.bitPattern == offset.bitPattern,
              (measurement.quantity(for: .appleWatchSimilarToLeadI) == nil) == (millivolts == nil) else {
            throw FixtureError.keyNotHonored(key: "timeSinceSampleStart/leadIVoltage", class: "HKElectrocardiogram.VoltageMeasurement")
        }
        return measurement
    }

    /// Objects the correlation's initializer admits: a blood-pressure pair, or one food entry.
    private static func correlationPlaceholders(for type: HKCorrelationType) throws -> Set<HKSample> {
        let pressure = HKUnit.millimeterOfMercury()
        let objects: [(HKQuantityTypeIdentifier, HKQuantity)] = if type.identifier == HKCorrelationTypeIdentifier.bloodPressure.rawValue {
            [
                (.bloodPressureSystolic, HKQuantity(unit: pressure, doubleValue: 120)),
                (.bloodPressureDiastolic, HKQuantity(unit: pressure, doubleValue: 80))
            ]
        } else {
            [(.dietaryEnergyConsumed, HKQuantity(unit: .kilocalorie(), doubleValue: 1))]
        }
        return Set(try objects.enumerated().map { index, object in
            let sample = HKQuantitySample(
                type: HKQuantityType(object.0),
                quantity: object.1,
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart
            )
            return try stored(sample, uuid: GoldenFixtures.uuid(0xCE + UInt8(index)))
        })
    }
}


#if !os(watchOS)
/// The clinical builders, which watchOS does not have.
extension StoredSampleFixtures {
    /// A CDA sample as an `HKDocumentQuery` returns it: with its document data, or without when `document` is nil.
    static func cdaDocument(title: String, document: Data?, facts: SampleFacts) throws -> HKCDADocumentSample {
        guard let documentType = HKObjectType.documentType(forIdentifier: .CDA) else {
            throw FixtureError.classNotConstructible("HKCDADocumentSample")
        }
        let sample = try seriesSample(HKCDADocumentSample.self, sampleType: documentType, facts: facts)
        guard let document else {
            return sample
        }
        let content = try instance(of: HKCDADocument.self, stating: ["internalDocumentData": document, "title": title])
        try restate(sample, with: ["document": content])
        guard sample.document?.documentData == document, sample.document?.title == title else {
            throw FixtureError.keyNotHonored(key: "document", class: "HKCDADocumentSample")
        }
        return sample
    }

    /// A clinical record carrying `resource` under `fhirVersion`, or no FHIR resource at all when it is nil.
    static func clinicalRecord(_ type: HKClinicalType, fhirVersion: HKFHIRVersion, resource: Data?, facts: SampleFacts) throws -> HKClinicalRecord {
        let record = try seriesSample(HKClinicalRecord.self, sampleType: type, facts: facts)
        guard let resource else {
            return record
        }
        let content = try instance(of: HKFHIRResource.self, stating: ["data": resource, "FHIRVersion": fhirVersion])
        try restate(record, with: ["FHIRResource": content])
        guard record.fhirResource?.data == resource else {
            throw FixtureError.keyNotHonored(key: "FHIRResource", class: "HKClinicalRecord")
        }
        return record
    }
}
#endif

#endif
