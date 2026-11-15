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
import HealthKit
import ModelsR4


/// An eating occasion groups independent nutrient measurements without taking over their identities or source facts.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitFoodContent: Sendable {
    private static let nutrientTypes: Set<HealthKitSourceType> = [
        .dietaryBiotin, .dietaryCaffeine, .dietaryCalcium, .dietaryCarbohydrates, .dietaryChloride, .dietaryCholesterol,
        .dietaryChromium, .dietaryCopper, .dietaryEnergyConsumed, .dietaryFatMonounsaturated, .dietaryFatPolyunsaturated,
        .dietaryFatSaturated, .dietaryFatTotal, .dietaryFiber, .dietaryFolate, .dietaryIodine, .dietaryIron,
        .dietaryMagnesium, .dietaryManganese, .dietaryMolybdenum, .dietaryNiacin, .dietaryPantothenicAcid, .dietaryPhosphorus,
        .dietaryPotassium, .dietaryProtein, .dietaryRiboflavin, .dietarySelenium, .dietarySodium, .dietarySugar,
        .dietaryThiamin, .dietaryVitaminA, .dietaryVitaminB12, .dietaryVitaminB6, .dietaryVitaminC, .dietaryVitaminD,
        .dietaryVitaminE, .dietaryVitaminK, .dietaryWater, .dietaryZinc
    ]

    let slot: HealthKitOutputSlot
    private let skeleton: Observation
    private let effective: EffectiveRule

    init(contract: MeasurementContract) throws(HealthKitContentDefect) {
        guard contract.effective == .period, contract.quantity == nil, contract.resultCodeSystem == nil else {
            throw HealthKitContentDefect("food requires a Period grouping without a scalar value")
        }
        slot = .primary(role: contract.id)
        skeleton = ObservationPlan.skeleton(
            code: CodeableConcept(coding: [Coding(contract.code)]), sourceType: .food, profiles: [contract.profile]
        )
        effective = EffectiveRule(contract)
    }

    static func validate(_ members: [HKSample]) throws {
        guard !members.isEmpty, Set(members.map(\.uuid)).count == members.count,
              members.allSatisfy({ sample in
                  guard sample is HKQuantitySample, let type = HealthKitSourceType(rawValue: sample.sampleType.identifier) else {
                      return false
                  }
                  return nutrientTypes.contains(type)
              }) else { throw HealthKitConversionError.ValueFailure.shapeInvalid }
    }

    func observation(_ correlation: HKCorrelation, metadata: HealthKitSampleMetadata, members: [RoledIdentifier]) throws -> Observation {
        var observation = skeleton
        observation.effective = try effective.value(start: correlation.startDate, end: correlation.endDate, zone: metadata.timeZone())
        observation.hasMember = members.map {
            Reference(identifier: $0.fhirIdentifier, type: FHIRPrimitive(FHIRURI(stringLiteral: ResourceType.observation.rawValue)))
        }
        return observation
    }
}


@available(iOS 18, macOS 15, watchOS 11, *)
extension HealthKitAssembly {
    func convertFood(
        _ correlation: HKCorrelation,
        content: HealthKitFoodContent,
        members: [HKSample],
        requests: [Request],
        request: Request
    ) throws -> [Conversion] {
        try HealthKitFoodContent.validate(members)
        guard requests.count == members.count, Set(correlation.objects.map(\.uuid)) == Set(members.map(\.uuid)) else {
            throw HealthKitConversionError.ValueFailure.shapeInvalid
        }
        let nutrients = try zip(members, requests).map { member, request in
            let conversions = try convert(member, request: request)
            guard conversions.count == 1, let conversion = conversions.first else { throw HealthKitConversionError.ValueFailure.shapeInvalid }
            return conversion
        }
        let metadata = HealthKitSampleMetadata(correlation, rule: .noContentKeys)
        let observation = try content.observation(correlation, metadata: metadata, members: nutrients.map(\.identifiers.primaryOutput))
        let parent = try graph(
            for: correlation, type: .food, metadata: metadata, outputs: [content.slot.draft(.observation(observation))], request: request
        )
        return [parent] + nutrients
    }
}

#endif
