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


/// Rebuilds a corpus vector's records the way HealthKit hands them back, through `StoredSampleFixtures`.
///
/// Each sample starts from its class's public initializer with values HealthKit admits, or as a bare instance
/// where the class has none or would refuse the vector, and is then restated with the vector's exact facts.
enum ContentCorpusSamples {
    enum RebuildError: Error, CustomStringConvertible {
        case unknownType(String)
        case unknownClass(String)
        case incompatibleUnit(type: String, unit: String)
        case notHonored(String)
        case notASample

        var description: String {
            switch self {
            case .unknownType(let type): "this HealthKit does not know \(type)"
            case .unknownClass(let name): "this HealthKit has no class \(name)"
            case let .incompatibleUnit(type, unit): "\(unit) does not measure \(type)"
            case .notHonored(let fact): "HealthKit no longer reads back the \(fact) the corpus writes"
            case .notASample: "the record converts through its own entry point"
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
    static func shape(_ source: ContentCorpusSource, uuid: UUID = uuid) -> StoredSampleFixtures.SeriesShape {
        StoredSampleFixtures.SeriesShape(
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
        let shape = shape(source)
        switch source.record {
        case let .quantity(type, value, unit):
            return try quantity(type: type, value: value, unit: unit, shape: shape)
        case let .category(type, value):
            return try category(type: type, value: value, shape: shape)
        case let .correlation(type, members):
            return try correlation(type: type, members: members, shape: shape)
        case let .bare(type, sampleClass):
            return try bare(type: type, sampleClass: sampleClass, shape: shape)
        case .workout, .stateOfMind, .assessment:
            return try reflection(source.record, shape: shape)
        case .cdaDocument, .clinicalRecord:
            return try ContentCorpusClinicalSamples.sample(source.record, shape: shape)
        case .electrocardiogram, .heartbeatSeries, .workoutRoute:
            throw RebuildError.notASample
        }
    }

    /// A quantity sample of any value over any interval: HealthKit validates both per type at creation, so the
    /// sample is a bare instance of the class its initializer would have chosen.
    static func quantity(type: String, value: Double, unit: String, shape: StoredSampleFixtures.SeriesShape) throws -> HKQuantitySample {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: type)) else {
            throw RebuildError.unknownType(type)
        }
        let healthKitUnit = HKUnit(from: unit)
        guard quantityType.is(compatibleWith: healthKitUnit) else {
            throw RebuildError.incompatibleUnit(type: type, unit: unit)
        }
        let sampleClass: HKQuantitySample.Type = quantityType.aggregationStyle == .cumulative
            ? HKCumulativeQuantitySample.self
            : HKDiscreteQuantitySample.self
        let sample = try StoredSampleFixtures.seriesSample(sampleClass, sampleType: quantityType, shape: shape)
        try StoredSampleFixtures.write(HKQuantity(unit: healthKitUnit, doubleValue: value), to: "quantity", of: sample)
        try StoredSampleFixtures.write(NSNumber(value: 1), to: "count", of: sample)
        let stated = sample.quantity.doubleValue(for: healthKitUnit)
        guard stated == value || (stated.isNaN && value.isNaN) else {
            throw RebuildError.notHonored("quantity")
        }
        return sample
    }

    /// A category sample with any raw value: HealthKit refuses an unadmitted one at creation, so the sample is bare.
    static func category(type: String, value: Int, shape: StoredSampleFixtures.SeriesShape) throws -> HKCategorySample {
        guard let categoryType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: type)) else {
            throw RebuildError.unknownType(type)
        }
        let sample = try StoredSampleFixtures.seriesSample(HKCategorySample.self, sampleType: categoryType, shape: shape)
        try StoredSampleFixtures.write(NSNumber(value: value), to: "value", of: sample)
        guard sample.value == value else {
            throw RebuildError.notHonored("category value")
        }
        return sample
    }

    /// A correlation with exactly `members`, which HealthKit's initializer would refuse unless it is one valid pair.
    private static func correlation(
        type: String,
        members: [ContentCorpusMember],
        shape: StoredSampleFixtures.SeriesShape
    ) throws -> HKCorrelation {
        let identifier = HKCorrelationTypeIdentifier(rawValue: type)
        guard let correlationType = HKObjectType.correlationType(forIdentifier: identifier) else {
            throw RebuildError.unknownType(type)
        }
        let correlation = HKCorrelation(
            type: correlationType,
            start: GoldenFixtures.sampleStart,
            end: GoldenFixtures.sampleStart,
            objects: try placeholders(for: identifier)
        )
        let objects = NSMutableDictionary()
        for (index, member) in members.enumerated() {
            var memberShape = shape
            memberShape.uuid = GoldenFixtures.uuid(0xD0 + UInt8(index))
            memberShape.device = nil
            memberShape.metadata = member.metadata.isEmpty ? nil : member.metadata.mapValues(\.value)
            memberShape.writer = .unattributed
            let sample = try quantity(type: member.type, value: member.value, unit: member.unit, shape: memberShape)
            let group = objects[sample.sampleType] as? NSMutableSet ?? NSMutableSet()
            group.add(sample)
            objects[sample.sampleType] = group
        }
        try StoredSampleFixtures.write(objects, to: "objects", of: correlation)
        guard correlation.objects.count == members.count else {
            throw RebuildError.notHonored("correlation objects")
        }
        return try StoredSampleFixtures.restated(correlation, shape: shape)
    }

    /// Objects the correlation's initializer admits: a blood-pressure pair, or one food entry. They carry no writer,
    /// the only attribution the initializer accepts for its objects, and are replaced by the vector's members.
    private static func placeholders(for identifier: HKCorrelationTypeIdentifier) throws -> Set<HKSample> {
        let pressure = HKUnit.millimeterOfMercury()
        let objects: [(HKQuantityTypeIdentifier, HKQuantity)] = identifier == .bloodPressure
            ? [(.bloodPressureSystolic, HKQuantity(unit: pressure, doubleValue: 120)), (.bloodPressureDiastolic, HKQuantity(unit: pressure, doubleValue: 80))]
            : [(.dietaryEnergyConsumed, HKQuantity(unit: .kilocalorie(), doubleValue: 1))]
        return Set(try objects.enumerated().map { index, object in
            let sample = HKQuantitySample(
                type: HKQuantityType(object.0),
                quantity: object.1,
                start: GoldenFixtures.sampleStart,
                end: GoldenFixtures.sampleStart
            )
            return try StoredSampleFixtures.stored(sample, uuid: GoldenFixtures.uuid(0xCE + UInt8(index)))
        })
    }

    /// A bare instance of a class the corpus feeds the plain entry point without a payload.
    private static func bare(type: String, sampleClass: String, shape: StoredSampleFixtures.SeriesShape) throws -> HKSample {
        guard let sampleType = bareSampleTypes[type] else {
            throw RebuildError.unknownType(type)
        }
        guard let healthKitClass = NSClassFromString(sampleClass) as? HKSample.Type else {
            throw RebuildError.unknownClass(sampleClass)
        }
        return try StoredSampleFixtures.seriesSample(healthKitClass, sampleType: sampleType, shape: shape)
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
