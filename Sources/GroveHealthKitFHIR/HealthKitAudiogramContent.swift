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


/// Air-conduction tests retain ear, exact frequency, masking and source clamping bounds.
@available(iOS 18, macOS 15, watchOS 11, *)
struct HealthKitAudiogramContent: Sendable {
    private enum Ear: String, Hashable {
        case left
        case right
    }

    private struct Coordinate: Hashable {
        let ear: Ear
        let frequency: Double
    }

    private struct Reading {
        let ear: Ear
        let value: Double
        // swiftlint:disable:next discouraged_optional_boolean - Older SDKs do not report masking.
        let masked: Bool?
        let lowerBound: Double?
        let upperBound: Double?
    }

    private let templates: [Coordinate: ComponentTemplate]
    private let sensitivity: QuantityTemplate
    private let frequency = QuantityTemplate(.init(system: "http://unitsofmeasure.org", code: "Hz", unit: "Hz", valueDomain: nil))

    init(_ contract: MeasurementContract) throws(HealthKitContentDefect) {
        var templates: [Coordinate: ComponentTemplate] = [:]
        for component in contract.components {
            let parts = component.id.split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let ear = Ear(rawValue: String(parts[0])),
                let frequency = Double(parts[1]), frequency.isFinite, frequency > 0,
                component.quantity?.code == "dB", let template = ComponentTemplate(component)
            else {
                throw HealthKitContentDefect("states an audiogram component without an ear, frequency or hearing-level quantity")
            }
            guard templates.updateValue(template, forKey: Coordinate(ear: ear, frequency: frequency)) == nil else {
                throw HealthKitContentDefect("states a duplicate audiogram ear and frequency")
            }
        }
        guard let quantity = contract.components.first?.quantity else {
            throw HealthKitContentDefect("states no audiogram sensitivity quantity")
        }
        self.templates = templates
        sensitivity = QuantityTemplate(quantity)
    }

    private static func readings(_ point: HKAudiogramSensitivityPoint) throws -> [Reading] {
        if #available(iOS 18.1, macOS 15.1, watchOS 11.1, *) {
            return try point.tests.map { test in
                guard test.type == .air else { throw HealthKitConversionError.ValueFailure.unsupportedValue(test.type.rawValue) }
                let ear: Ear
                switch test.side {
                case .left: ear = .left
                case .right: ear = .right
                @unknown default: throw HealthKitConversionError.ValueFailure.unsupportedValue(test.side.rawValue)
                }
                return Reading(
                    ear: ear,
                    value: test.sensitivity.doubleValue(for: .decibelHearingLevel()),
                    masked: test.masked,
                    lowerBound: test.clampingRange?.lowerBound?.doubleValue(for: .decibelHearingLevel()),
                    upperBound: test.clampingRange?.upperBound?.doubleValue(for: .decibelHearingLevel())
                )
            }
        }
        return [(Ear.left, point.leftEarSensitivity), (.right, point.rightEarSensitivity)].compactMap { ear, value in
            value.map { Reading(ear: ear, value: $0.doubleValue(for: .decibelHearingLevel()), masked: nil, lowerBound: nil, upperBound: nil) }
        }
    }

    func apply(to observation: inout Observation, sample: HKAudiogramSample) throws {
        guard (1...30).contains(sample.sensitivityPoints.count) else { throw HealthKitConversionError.ValueFailure.shapeInvalid }
        var components: [ObservationComponent] = []
        var frequencies: Set<Double> = []
        for point in sample.sensitivityPoints.sorted(by: { $0.frequency.doubleValue(for: .hertz()) < $1.frequency.doubleValue(for: .hertz()) }) {
            let hertz = point.frequency.doubleValue(for: .hertz())
            guard hertz.isFinite, hertz > 0, frequencies.insert(hertz).inserted else {
                throw HealthKitConversionError.ValueFailure.shapeInvalid
            }
            let readings = try Self.readings(point)
            guard !readings.isEmpty else { throw HealthKitConversionError.ValueFailure.shapeInvalid }
            var seen: Set<Ear> = []
            for reading in readings.sorted(by: { $0.ear.rawValue < $1.ear.rawValue }) {
                guard seen.insert(reading.ear).inserted else { throw HealthKitConversionError.ValueFailure.shapeInvalid }
                components.append(try component(reading, hertz: hertz))
            }
        }
        observation.component = components
    }

    private func component(_ reading: Reading, hertz: Double) throws -> ObservationComponent {
        let coordinate = Coordinate(ear: reading.ear, frequency: hertz)
        var component: ObservationComponent
        if let template = templates[coordinate] {
            component = try template.component(reading.value)
        } else {
            let value = try frequency.quantity(hertz)
            guard let frequencyValue = value.value?.value?.decimal else { throw HealthKitConversionError.ValueFailure.shapeInvalid }
            let label = "Air conduction threshold, \(reading.ear.rawValue) ear, \(frequencyValue) Hz"
            component = try ObservationComponent(
                code: CodeableConcept(text: label.asFHIRStringPrimitive()),
                value: .quantity(sensitivity.quantity(reading.value))
            )
        }
        var details = [
            Extension(url: "frequency", value: .quantity(try frequency.quantity(hertz))),
            Extension(url: "ear", value: .code(reading.ear.rawValue.asFHIRStringPrimitive())),
            Extension(url: "conduction", value: .code("air"))
        ]
        if let masked = reading.masked { details.append(Extension(url: "masked", value: .boolean(FHIRPrimitive(FHIRBool(masked))))) }
        if let low = reading.lowerBound, let high = reading.upperBound, low >= high {
            throw HealthKitConversionError.ValueFailure.shapeInvalid
        }
        if reading.lowerBound != nil || reading.upperBound != nil {
            let range = try ModelsR4.Range(
                high: reading.upperBound.map { try sensitivity.quantity($0) },
                low: reading.lowerBound.map { try sensitivity.quantity($0) }
            )
            details.append(Extension(url: "clampingRange", value: .range(range)))
        }
        component.extension = [Extension(extension: details, url: Canonicals.healthKitAudiogramTestDetails)]
        return component
    }
}

#endif
