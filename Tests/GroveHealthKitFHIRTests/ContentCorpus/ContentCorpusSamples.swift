//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import Foundation
@testable import GroveHealthKitFHIR
import HealthKit


/// Rebuilds a corpus vector's records the way HealthKit hands them back: it reads the vector's data into HealthKit
/// types and lets `StoredSampleFixtures`, the only code that touches HealthKit's private storage, build them.
enum ContentCorpusSamples {
    /// Why a vector's record cannot be rebuilt here.
    enum RebuildError: Error, CustomStringConvertible {
        /// This HealthKit does not know the type identifier.
        case unknownType(String)
        /// This HealthKit has no class of that name.
        case unknownClass(String)
        /// HealthKit would trap on the fact, so no sample can state it.
        case unstatable(String)
        /// The record converts through its own entry point, not as a plain sample.
        case notASample
        /// This platform has no such record; the vector is verified on the others.
        case unavailableHere(String)

        var description: String {
            switch self {
            case .unknownType(let type): "this HealthKit does not know \(type)"
            case .unknownClass(let name): "this HealthKit has no class \(name)"
            case .unstatable(let fact): "HealthKit traps on \(fact), so no sample states it"
            case .notASample: "the record converts through its own entry point"
            case .unavailableHere(let type): "this platform has no \(type)"
            }
        }
    }

    /// The UUID of every vector's record; members and symptoms take their own ordinals.
    static let uuid = GoldenFixtures.uuid(0xC0)

    /// The bare classes the plain entry point is fed, by the sample type they carry.
    private static let bareSampleTypes: [String: HKSampleType] = [
        HKObjectType.audiogramSampleType().identifier: HKObjectType.audiogramSampleType(),
        HKObjectType.visionPrescriptionType().identifier: HKObjectType.visionPrescriptionType(),
        HKObjectType.medicationDoseEventType().identifier: HKObjectType.medicationDoseEventType(),
        HKObjectType.electrocardiogramType().identifier: HKObjectType.electrocardiogramType(),
        HKSeriesType.heartbeat().identifier: HKSeriesType.heartbeat(),
        HKSeriesType.workoutRoute().identifier: HKSeriesType.workoutRoute()
    ]

    /// Every fact of `source` except its payload, under `uuid`.
    static func facts(_ source: ContentCorpusSource, uuid: UUID = uuid) -> StoredSampleFixtures.SampleFacts {
        StoredSampleFixtures.SampleFacts(
            uuid: uuid,
            start: Date(timeIntervalSince1970: source.start),
            end: Date(timeIntervalSince1970: source.end),
            device: source.device.map { $0 == .watch ? GoldenFixtures.watch : GoldenFixtures.watchWithoutUnitToken },
            metadata: source.metadata.isEmpty ? nil : source.metadata.mapValues(\.value),
            writer: source.writer == .foreign ? GoldenFixtures.foreignWriter : .unattributed
        )
    }

    /// The sample a vector feeds the plain sample entry point.
    static func sample(_ source: ContentCorpusSource) throws -> HKSample {
        let facts = facts(source)
        switch source.record {
        case let .quantity(type, value, unit):
            return try quantity(type: type, value: value, unit: unit, facts: facts)
        case let .category(type, value):
            return try StoredSampleFixtures.categorySample(try categoryType(type), value: value, facts: facts)
        case let .correlation(type, members):
            return try correlation(type: type, members: members, facts: facts)
        case .workout, .stateOfMind, .assessment:
            return try initializedSample(source.record, facts: facts)
        case let .bare(type, sampleClass):
            return try bare(type: type, sampleClass: sampleClass, facts: facts)
        case .cdaDocument, .clinicalRecord:
            return try clinicalSample(source.record, facts: facts)
        case .electrocardiogram, .heartbeatSeries, .workoutRoute:
            throw RebuildError.notASample
        }
    }

    /// A quantity sample stating `value` in `unit`.
    static func quantity(type: String, value: Double, unit: String, facts: StoredSampleFixtures.SampleFacts) throws -> HKQuantitySample {
        try StoredSampleFixtures.quantitySample(try quantityType(type), value: value, unit: HKUnit(from: unit), facts: facts)
    }

    /// The quantity type an identifier names.
    static func quantityType(_ type: String) throws -> HKQuantityType {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: type)) else {
            throw RebuildError.unknownType(type)
        }
        return quantityType
    }

    /// The category type an identifier names.
    static func categoryType(_ type: String) throws -> HKCategoryType {
        guard let categoryType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: type)) else {
            throw RebuildError.unknownType(type)
        }
        return categoryType
    }

    /// A correlation of exactly `members`, each stating its own metadata, attributed to no writer and no device.
    private static func correlation(
        type: String,
        members: [ContentCorpusMember],
        facts: StoredSampleFixtures.SampleFacts
    ) throws -> HKCorrelation {
        guard let correlationType = HKObjectType.correlationType(forIdentifier: HKCorrelationTypeIdentifier(rawValue: type)) else {
            throw RebuildError.unknownType(type)
        }
        let objects = try members.enumerated().map { index, member in
            var memberFacts = facts
            memberFacts.uuid = GoldenFixtures.uuid(0xD0 + UInt8(index))
            memberFacts.device = nil
            memberFacts.metadata = member.metadata.isEmpty ? nil : member.metadata.mapValues(\.value)
            memberFacts.writer = .unattributed
            return try quantity(type: member.type, value: member.value, unit: member.unit, facts: memberFacts)
        }
        return try StoredSampleFixtures.correlation(correlationType, objects: objects, facts: facts)
    }

    /// A workout, State of Mind or scored assessment: built through its initializer, which validates the payload,
    /// then restated with the vector's exact payload and facts.
    private static func initializedSample(_ record: ContentCorpusRecord, facts: StoredSampleFixtures.SampleFacts) throws -> HKSample {
        switch record {
        case let .workout(activity, duration, statistics):
            let statistics = try statistics.map { statistic in
                StoredSampleFixtures.WorkoutStatistic(
                    type: try quantityType(statistic.type),
                    unit: HKUnit(from: statistic.unit),
                    sum: statistic.sum,
                    average: statistic.average,
                    minimum: statistic.minimum,
                    maximum: statistic.maximum
                )
            }
            return try StoredSampleFixtures.workout(activity: activity, duration: duration, statistics: statistics, facts: facts)
        case let .stateOfMind(kind, valence, labels, associations):
            // HealthKit classifies the valence when it is read and traps outside -1...1, so no vector states one.
            guard (-1...1).contains(valence) else {
                throw RebuildError.unstatable("valence \(valence)")
            }
            return try StoredSampleFixtures.stateOfMind(kind: kind, valence: valence, labels: labels, associations: associations, facts: facts)
        case let .assessment(type, score):
            let identifier = HKScoredAssessmentTypeIdentifier(rawValue: type)
            guard let assessment = try StoredSampleFixtures.scoredAssessment(identifier, score: score, facts: facts) else {
                throw RebuildError.unknownType(type)
            }
            return assessment
        default:
            throw RebuildError.notASample
        }
    }

    /// A bare instance of a class the corpus feeds the plain entry point without a payload.
    private static func bare(type: String, sampleClass: String, facts: StoredSampleFixtures.SampleFacts) throws -> HKSample {
        guard let sampleType = bareSampleTypes[type] else {
            throw RebuildError.unknownType(type)
        }
        guard let healthKitClass = NSClassFromString(sampleClass) as? HKSample.Type else {
            throw RebuildError.unknownClass(sampleClass)
        }
        return try StoredSampleFixtures.seriesSample(healthKitClass, sampleType: sampleType, facts: facts)
    }

    /// A CDA document or clinical record, which watchOS does not have.
    private static func clinicalSample(_ record: ContentCorpusRecord, facts: StoredSampleFixtures.SampleFacts) throws -> HKSample {
        #if os(watchOS)
        throw RebuildError.unavailableHere(record.sourceTypeIdentifier)
        #else
        switch record {
        case let .cdaDocument(title, document):
            return try StoredSampleFixtures.cdaDocument(title: title, document: document.map { Data($0.utf8) }, facts: facts)
        case let .clinicalRecord(type, fhirVersion, resource):
            guard let clinicalType = HKObjectType.clinicalType(forIdentifier: HKClinicalTypeIdentifier(rawValue: type)) else {
                throw RebuildError.unknownType(type)
            }
            return try StoredSampleFixtures.clinicalRecord(
                clinicalType,
                fhirVersion: try HKFHIRVersion(fromVersionString: fhirVersion),
                resource: resource.map { Data($0.utf8) },
                facts: facts
            )
        default:
            throw RebuildError.notASample
        }
        #endif
    }
}


extension ContentCorpusMetadataValue {
    /// The value HealthKit keeps, bridged to the Foundation object it stores.
    var value: any Sendable {
        switch self {
        case .string(let text): text
        case .integer(let number): number
        case .double(let number): number
        case .boolean(let flag): flag
        }
    }
}

#endif
