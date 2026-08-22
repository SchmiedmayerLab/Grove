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
import Testing


/// Converts a synthesized sample for *every* supported quantity row rather than the hand-picked
/// few, so a wrong unit, a dropped profile claim, or a mis-generated code fails here instead of
/// reaching a producer's conformance lane.
@Suite
struct HealthKitFHIRCatalogConversionTests {
    /// Rows whose value is not a plain quantity sample: they are covered by the ECG, category,
    /// correlation, and aggregate suites, which supply the evidence those shapes require.
    static let identifiers: [String] = HealthKitFHIRCatalog.entries
        .filter { $0.implementationStatus == .supported }
        .map(\.sourceTypeIdentifier)
        .filter { identifier in
            guard let binding = HealthKitFHIRCatalog.binding(forSourceTypeIdentifier: identifier) else {
                return false
            }
            if case .quantity = binding {
                return true
            }
            return false
        }

    private let converter = HealthKitFHIRConverter()
    private let timestamp = Date(timeIntervalSince1970: 1_787_148_600)

    private var context: HealthKitFHIRConversionContext {
        HealthKitFHIRConversionContext(
            subject: Reference(reference: "Patient/example"),
            converter: HealthKitFHIRApplication(
                name: "Example Study",
                bundleIdentifier: "org.grovealliance.example-study",
                version: "2.0.0 (42)"
            ),
            graphIdentifierSystem: "https://study.example.org/fhir/identifiers/mobile-graph",
            conversionInstant: timestamp
        )
    }

    /// HealthKit aborts the process when a type's required metadata is missing, so the few
    /// types that demand a key are given one before the sample is built.
    private func requiredMetadata(for identifier: String) -> [String: Any] {
        switch identifier {
        case HKQuantityTypeIdentifier.insulinDelivery.rawValue:
            [HKMetadataKeyInsulinDeliveryReason: HKInsulinDeliveryReason.basal.rawValue]
        default:
            [:]
        }
    }

    @Test("Every supported quantity row converts to its exact catalog contract", arguments: identifiers)
    func supportedQuantityRowConverts(identifier: String) throws {
        guard case .quantity(let contract, let unit)? =
                HealthKitFHIRCatalog.binding(forSourceTypeIdentifier: identifier) else {
            Issue.record("\(identifier) lost its quantity binding")
            return
        }
        // HealthKit traps rather than throws on a mismatched unit, so the binding is checked
        // against the platform type before a sample is built.
        guard let type = HKObjectType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: identifier)) else {
            Issue.record("\(identifier) is bound as a quantity but is not a platform quantity type")
            return
        }
        guard type.is(compatibleWith: unit) else {
            Issue.record("\(identifier) is bound to \(unit), which its platform type does not accept")
            return
        }
        // A period metric needs a real interval; an instant metric is a zero-length sample.
        let interval: TimeInterval = contract.effective == .period ? 60 : 0
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: 1),
            start: timestamp,
            end: timestamp.addingTimeInterval(interval),
            metadata: requiredMetadata(for: identifier)
        )

        let observation = try converter.convert(sample, context: context).observation

        #expect(observation.meta?.profile == contract.profiles, "\(identifier) profile claim")
        let codings = try #require(observation.code.coding, "\(identifier) has no code")
        let code = try #require(codings.first)
        #expect(code.system?.value?.url.absoluteString == contract.code.system, "\(identifier) code system")
        #expect(code.code?.value?.string == contract.code.code, "\(identifier) code")
        #expect(codings.last?.system == GroveFHIRCanonical.healthKitSourceType, "\(identifier) source coding")
        #expect(codings.last?.code?.value?.string == identifier, "\(identifier) source type")
        let emittedPeriod = if case .period = observation.effective { true } else { false }
        #expect(emittedPeriod == (contract.effective == .period), "\(identifier) effective kind")
        guard case .quantity(let value)? = observation.value else {
            Issue.record("\(identifier) did not emit a value Quantity")
            return
        }
        #expect(value.system?.value?.url.absoluteString == contract.quantity?.system, "\(identifier) unit system")
        #expect(value.code?.value?.string == contract.quantity?.code, "\(identifier) unit code")
    }

    @Test("The matrix covers every quantity-bound row the catalog admits")
    func matrixIsNotSilentlyEmpty() {
        // A refactor that stopped resolving bindings would make the parameterized test vacuous.
        #expect(Self.identifiers.count > 90, "only \(Self.identifiers.count) quantity rows were collected")
        #expect(Set(Self.identifiers).count == Self.identifiers.count)
    }
}

#endif
