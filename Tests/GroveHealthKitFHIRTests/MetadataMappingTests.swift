//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)

import FHIRModelsExtensions
@testable import GroveHealthKitFHIR
import HealthKit
import ModelsR4
import Testing


@Suite
struct MetadataMappingTests {
    var subject: Reference {
        Reference(reference: "Patient/example")
    }

    @Test
    func metadataHandling() throws {
        func imp<T>(_: T.Type, _ value: T, sourceLocation: SourceLocation = #_sourceLocation) throws -> ModelsR4.Extension.ValueX {
            let metadataKey = "org.grovealliance.GroveHealthKitFHIRTests.TestMetadataEntry"
            let sample = HKQuantitySample(
                type: HKQuantityType(.stepCount),
                quantity: HKQuantity(unit: .count(), doubleValue: 17),
                start: .now,
                end: .now,
                metadata: [metadataKey: value]
            )
            let resource = try sample.resource(subject: subject)
            let observation = try #require(resource.get(if: Observation.self), sourceLocation: sourceLocation)
            let entry = try #require(observation.metadataEntry(forKey: metadataKey), sourceLocation: sourceLocation)
            return try #require(entry.extensions(for: "value").first?.value, sourceLocation: sourceLocation)
        }

        #expect(try imp(String.self, "Hey") == .string("Hey"))
        #expect(try imp(NSString.self, "Hey") == .string("Hey"))
        #expect(try imp(Bool.self, false) == .boolean(false))
        #expect(try imp(Bool.self, true) == .boolean(true))
        #expect(
            try imp(Date.self, .referenceDate) == .dateTime(FHIRPrimitive(DateTime(date: .referenceDate)))
        )
        #expect(try imp(Double.self, 0) == .decimal(0.asFHIRDecimalPrimitive()))
        #expect(try imp(Double.self, 1) == .decimal(1.asFHIRDecimalPrimitive()))
        #expect(try imp(Float.self, 0) == .decimal(0.asFHIRDecimalPrimitive()))
        #expect(try imp(Float.self, 1) == .decimal(1.asFHIRDecimalPrimitive()))
        #expect(try imp(CGFloat.self, 0) == .decimal(0.asFHIRDecimalPrimitive()))
        #expect(try imp(CGFloat.self, 1) == .decimal(1.asFHIRDecimalPrimitive()))
        #expect(try imp(Int.self, 0) == .decimal(0.asFHIRDecimalPrimitive()))
        #expect(try imp(Int.self, 1) == .decimal(1.asFHIRDecimalPrimitive()))
        #expect(try imp(Int.self, 2) == .decimal(2.asFHIRDecimalPrimitive()))
        
        #expect(try imp(NSNumber.self, .init(value: 0)) == .decimal(0.asFHIRDecimalPrimitive()))
        #expect(try imp(NSNumber.self, .init(value: 1)) == .decimal(1.asFHIRDecimalPrimitive()))
        #expect(try imp(NSNumber.self, .init(value: 2)) == .decimal(2.asFHIRDecimalPrimitive()))
        #expect(try imp(NSNumber.self, .init(value: 0.0)) == .decimal(0.asFHIRDecimalPrimitive()))
        #expect(try imp(NSNumber.self, .init(value: 1.0)) == .decimal(1.asFHIRDecimalPrimitive()))
        #expect(try imp(NSNumber.self, .init(value: 2.0)) == .decimal(2.asFHIRDecimalPrimitive()))
        #expect(try imp(NSNumber.self, .init(value: false)) == .boolean(false))
        #expect(try imp(NSNumber.self, .init(value: true)) == .boolean(true))
    }

    /// Layer 4 carries whatever survives layers 1-3, so a key promoted to a component must not also
    /// appear in the metadata envelope.
    @Test
    func promotedKeysAreNotDuplicatedIntoTheEnvelope() throws {
        let sample = HKCategorySample(
            type: HKCategoryType(.lowCardioFitnessEvent),
            value: HKCategoryValueLowCardioFitnessEvent.lowFitness.rawValue,
            start: .now,
            end: .now,
            metadata: [
                HKMetadataKeyLowCardioFitnessEventThreshold: HKQuantity(unit: HKUnit(from: "ml/(kg*min)"), doubleValue: 41),
                HKMetadataKeyVO2MaxValue: HKQuantity(unit: HKUnit(from: "ml/(kg*min)"), doubleValue: 38),
                HKMetadataKeyTimeZone: "America/Los_Angeles",
                HKMetadataKeyExternalUUID: "some-external-id"
            ]
        )
        let observation = try #require(sample.resource(subject: subject).get(if: Observation.self))
        let componentKeys = Set((observation.component ?? [])
            .flatMap { $0.code.coding ?? [] }
            .filter { $0.system == GroveFHIRVocabulary.healthKitMetadataKey }
            .compactMap { $0.code?.value?.string })
        #expect(componentKeys == [HKMetadataKeyLowCardioFitnessEventThreshold, HKMetadataKeyVO2MaxValue])
        for key in componentKeys {
            #expect(observation.metadataEntry(forKey: key) == nil)
        }
        // The timezone is routed to effective[x], and everything else still lands in the envelope.
        #expect(observation.metadataEntry(forKey: HKMetadataKeyTimeZone) == nil)
        #expect(observation.metadataEntry(forKey: HKMetadataKeyExternalUUID) != nil)
    }
}


extension Observation {
    /// The `grove-platform-metadata` entry for a metadata key, if the envelope carries one.
    ///
    /// Resolves through the identifier rather than a literal, so the canonical spelling and every
    /// spelling it superseded are both accepted -- which is what an existing resource will carry.
    fileprivate func metadataEntry(forKey key: String) -> Extension? {
        extensions(for: FHIRExtensionURL.metadata).first { entry in
            entry.extensions(for: "key").contains { $0.value == .coding(Coding(
                code: key.asFHIRStringPrimitive(),
                system: GroveFHIRVocabulary.healthKitMetadataKey
            ))
            }
        }
    }
}


extension Date {
    fileprivate static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)
}

#endif
