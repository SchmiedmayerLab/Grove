//
// This source file is part of the Grove open-source project
//
// SPDX-FileCopyrightText: 2026 Schmiedmayer Lab and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

#if canImport(HealthKit)
public import Foundation
import GroveFHIRContract
public import HealthKit
public import ModelsR4


/// Why an extracted measurement cannot become a HealthKit sample.
public enum QuestionnaireHealthKitSampleError: Error, Equatable {
    case measurementNotMappable(id: String)
    case unitNotMappable(code: String)
    case valueMissing(id: String)
    case componentMissing(id: String, code: String)
    case authoredMissing
}


/// Turns a questionnaire pair into the HealthKit samples its marked items describe.
///
/// This serves the app that captures a response and keeps HealthKit as its store: the
/// instrument's SDC markings drive the same extraction the exchange projection uses, and the
/// results land as samples the HealthKit adapter later converts like any other reading.
/// The map covers the self-reportable measurements HealthKit models; an unmapped measurement
/// refuses rather than guessing a type.
public enum QuestionnaireHealthKitSampleProjection {
    /// Extracts every marked measurement and returns one sample per measurement.
    public static func samples(
        questionnaire: ModelsR4.Questionnaire,
        response: ModelsR4.QuestionnaireResponse
    ) throws -> [HKSample] {
        let extracted = try QuestionnaireObservationExtractor(
            questionnaire: questionnaire,
            response: response
        ).extract()
        guard let authored = response.authored?.value, let date = try? authored.asNSDate() else {
            throw QuestionnaireHealthKitSampleError.authoredMissing
        }
        return try extracted.map { measurement in
            try sample(for: measurement, date: date)
        }
    }

    // MARK: Mapping

    private static func sample(
        for measurement: ExtractedMeasurement,
        date: Date
    ) throws -> HKSample {
        if measurement.contract.id == "blood-pressure" {
            return try bloodPressureCorrelation(for: measurement, date: date)
        }
        guard let type = quantityType(for: measurement.contract.id) else {
            throw QuestionnaireHealthKitSampleError.measurementNotMappable(id: measurement.contract.id)
        }
        guard case .quantity(let quantity) = measurement.value else {
            throw QuestionnaireHealthKitSampleError.valueMissing(id: measurement.contract.id)
        }
        return HKQuantitySample(
            type: HKQuantityType(type),
            quantity: try healthKitQuantity(quantity),
            start: date,
            end: date
        )
    }

    private static func bloodPressureCorrelation(
        for measurement: ExtractedMeasurement,
        date: Date
    ) throws -> HKCorrelation {
        guard case .components(let components) = measurement.value else {
            throw QuestionnaireHealthKitSampleError.valueMissing(id: measurement.contract.id)
        }
        func component(_ code: String, _ type: HKQuantityTypeIdentifier) throws -> HKQuantitySample {
            guard let component = components.first(where: { $0.code.code == code }) else {
                throw QuestionnaireHealthKitSampleError.componentMissing(
                    id: measurement.contract.id,
                    code: code
                )
            }
            return HKQuantitySample(
                type: HKQuantityType(type),
                quantity: try healthKitQuantity(component.value),
                start: date,
                end: date
            )
        }
        let systolic = try component("8480-6", .bloodPressureSystolic)
        let diastolic = try component("8462-4", .bloodPressureDiastolic)
        return HKCorrelation(
            type: HKCorrelationType(.bloodPressure),
            start: date,
            end: date,
            objects: [systolic, diastolic]
        )
    }

    private static func quantityType(for measurementID: String) -> HKQuantityTypeIdentifier? {
        switch measurementID {
        case "body-weight": .bodyMass
        case "blood-glucose-unspecified-specimen": .bloodGlucose
        case "step-count": .stepCount
        case "body-height": .height
        case "heart-rate": .heartRate
        case "body-temperature": .bodyTemperature
        default: nil
        }
    }

    private static func healthKitQuantity(_ quantity: Quantity) throws -> HKQuantity {
        guard let decimal = quantity.value?.value?.decimal else {
            throw QuestionnaireHealthKitSampleError.valueMissing(id: quantity.code?.value?.string ?? "")
        }
        let code = quantity.code?.value?.string ?? ""
        guard let unit = healthKitUnit(forUCUM: code) else {
            throw QuestionnaireHealthKitSampleError.unitNotMappable(code: code)
        }
        return HKQuantity(unit: unit, doubleValue: NSDecimalNumber(decimal: decimal).doubleValue)
    }

    private static func healthKitUnit(forUCUM code: String) -> HKUnit? {
        switch code {
        case "kg": .gramUnit(with: .kilo)
        case "mm[Hg]": .millimeterOfMercury()
        case "mg/dL": HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
        case "{steps}", "1": .count()
        case "cm": .meterUnit(with: .centi)
        case "/min": HKUnit.count().unitDivided(by: .minute())
        case "Cel": .degreeCelsius()
        default: nil
        }
    }
}
#endif
