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


/// The reverse projection reads the effective each measurement's profile admits, refuses every other with a typed
/// error, and never reaches a HealthKit initializer that raises.
@Suite("HealthKit Sample Projection Effective Times")
struct HealthKitSampleProjectionEffectiveTests {
    /// The effective an observation states.
    enum Effective: Sendable, CustomTestStringConvertible {
        case instant(String)
        case period(start: String?, end: String?)

        var testDescription: String {
            switch self {
            case .instant(let instant): instant
            case let .period(start, end): "\(start ?? "open")/\(end ?? "open")"
            }
        }
    }

    /// 2026-08-24T07:41:00-07:00.
    private static let start = "2026-08-24T07:41:00-07:00"
    /// A minute after ``start``.
    private static let minuteLater = "2026-08-24T07:42:00-07:00"
    /// The guide's ECG average heart rate is a heart rate whose lineage is the ECG.
    private static let electrocardiogramLineage = HKObjectType.electrocardiogramType().identifier

    /// An Observation of `contract` stating `effective`, `value` in the contract's unit and, when given, its HealthKit
    /// lineage.
    private static func observation(
        _ contract: MeasurementContract,
        _ effective: Effective,
        value: Decimal = 1,
        lineage: String? = nil
    ) throws -> ModelsR4.Observation {
        var observation = Observation(
            code: CodeableConcept(coding: [
                Coding(code: contract.code.code.asFHIRStringPrimitive(), system: FHIRPrimitive(FHIRURI(stringLiteral: contract.code.system)))
            ]),
            status: FHIRPrimitive(.final)
        )
        switch effective {
        case .instant(let instant):
            observation.effective = .dateTime(FHIRPrimitive(try DateTime(instant)))
        case let .period(start, end):
            observation.effective = .period(Period(
                end: try end.map { FHIRPrimitive(try DateTime($0)) },
                start: try start.map { FHIRPrimitive(try DateTime($0)) }
            ))
        }
        if let quantity = contract.quantity {
            observation.value = .quantity(Quantity(
                code: quantity.code.asFHIRStringPrimitive(),
                system: FHIRPrimitive(FHIRURI(stringLiteral: quantity.system)),
                unit: quantity.unit.asFHIRStringPrimitive(),
                value: FHIRPrimitive(FHIRDecimal(value))
            ))
        }
        if let lineage {
            observation.extension = [Extension(url: Canonicals.healthKitSourceTypeExtension, value: .code(lineage.asFHIRStringPrimitive()))]
        }
        return observation
    }

    /// Why `observation` does not project, or `nil` when it does.
    private static func refusal(_ observation: ModelsR4.Observation) -> HealthKitSampleProjectionError? {
        do {
            _ = try observation.healthKitSample()
            return nil
        } catch {
            return error
        }
    }

    /// A UTC date-time lexeme of `date`, whole seconds.
    private static func lexeme(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    @Test("A Period measurement projects its Period, up to the longest HealthKit allows")
    func periodMeasurementProjectsItsPeriod() throws {
        let steps = try #require(try Self.observation(MeasurementCatalog.stepCount, .period(start: Self.start, end: Self.minuteLater), value: 120)
            .healthKitSample() as? HKQuantitySample)
        #expect(steps.quantityType == HKQuantityType(.stepCount))
        #expect(steps.startDate == (try DateTime(Self.start).asNSDate()))
        #expect(steps.endDate == (try DateTime(Self.minuteLater).asNSDate()))
        #expect(steps.quantity.doubleValue(for: .count()) == 120)
        #expect(steps.metadata?[HKMetadataKeyTimeZone] as? String == "GMT-0700")

        let type = HKQuantityType(.stepCount)
        try #require(type.isMaximumDurationRestricted)
        let start = try DateTime(Self.start).asNSDate()
        let longest = Self.lexeme(start.addingTimeInterval(type.maximumAllowedDuration))
        #expect(throws: Never.self) {
            try Self.observation(MeasurementCatalog.stepCount, .period(start: Self.start, end: longest)).healthKitSample()
        }
        let tooLong = Self.lexeme(start.addingTimeInterval(type.maximumAllowedDuration + 1))
        #expect(Self.refusal(try Self.observation(MeasurementCatalog.stepCount, .period(start: Self.start, end: tooLong)))
            == .effectivePeriodInvalid(id: "step-count"))
    }

    @Test(
        "An effective of a datatype the profile does not admit refuses at effective[x]",
        arguments: [
            (MeasurementCatalog.stepCount.id, Effective.instant(start)),
            (MeasurementCatalog.bodyWeight.id, .period(start: start, end: minuteLater)),
            (HealthKitMeasurementCatalog.environmentalAudioExposure.id, .instant(start))
        ]
    )
    func effectiveTypeNotAdmitted(id: String, effective: Effective) throws {
        let contract = try #require(HealthKitSampleProjection.measurements.values.first { $0.id == id })
        let refusal = try #require(Self.refusal(try Self.observation(contract, effective)))
        #expect(refusal == .effectiveTypeNotAdmitted(id: id))
        #expect(refusal.diagnostic.code == "mobile-input.effective-period-invalid")
        #expect(refusal.diagnostic.location == "Observation.effective[x]")
    }

    @Test(
        "A Period HealthKit cannot state as the sample's interval refuses at effectivePeriod",
        arguments: [
            (MeasurementCatalog.stepCount.id, Effective.period(start: start, end: nil)),
            (MeasurementCatalog.stepCount.id, .period(start: nil, end: start)),
            (MeasurementCatalog.stepCount.id, .period(start: start, end: start)),
            (MeasurementCatalog.stepCount.id, .period(start: minuteLater, end: start)),
            (MeasurementCatalog.dietaryEnergy.id, .period(start: minuteLater, end: start)),
            // HealthKit raises on an audio exposure shorter than a millisecond.
            (HealthKitMeasurementCatalog.environmentalAudioExposure.id, .period(start: start, end: start))
        ]
    )
    func invalidPeriodRefuses(id: String, effective: Effective) throws {
        let contract = try #require(HealthKitSampleProjection.measurements.values.first { $0.id == id })
        let refusal = try #require(Self.refusal(try Self.observation(contract, effective)))
        #expect(refusal == .effectivePeriodInvalid(id: id))
        #expect(refusal.diagnostic.code == "mobile-input.effective-period-invalid")
        #expect(refusal.diagnostic.location == "Observation.effectivePeriod")
    }

    @Test("A measurement HealthKit cannot be written as refuses before its effective is read")
    func unwritableMeasurementRefusesFirst() throws {
        for effective in [Effective.instant(Self.start), .period(start: Self.start, end: Self.minuteLater), .period(start: nil, end: nil)] {
            #expect(Self.refusal(try Self.observation(MeasurementCatalog.distance, effective)) == .measurementNotMappable(id: "distance"))
        }
        // HealthKit raises on an insulin delivery without the delivery reason, which the projection does not restore.
        let insulin = try Self.observation(HealthKitMeasurementCatalog.insulinDelivery, .period(start: Self.start, end: Self.minuteLater))
        #expect(Self.refusal(insulin) == .measurementNotMappable(id: "insulin-delivery"))
        let averageHeartRate = try Self.observation(
            MeasurementCatalog.heartRate,
            .instant(Self.start),
            value: 72,
            lineage: Self.electrocardiogramLineage
        )
        #expect(Self.refusal(averageHeartRate) == .measurementNotMappable(id: "heart-rate"))
        let ownLineage = try Self.observation(MeasurementCatalog.heartRate, .instant(Self.start), value: 72, lineage: HKQuantityTypeIdentifier.heartRate.rawValue)
        #expect(Self.refusal(ownLineage) == nil)
    }

    @Test("Every golden's Observations project or refuse without trapping, never for their effective", arguments: GoldenCase.all)
    func goldenObservationsProject(_ goldenCase: GoldenCase) throws {
        let graph = try goldenCase.output().graph
        let projection = graph.healthKitSamples()
        for failure in projection.failures {
            switch failure.error {
            case .effectiveMissing, .effectiveTypeNotAdmitted, .effectivePeriodInvalid:
                Issue.record("\(failure.fullURL.value?.url.absoluteString ?? "") refuses for its effective: \(failure.error)")
            default:
                break
            }
        }
        let averageHeartRates = (graph.bundle.entry ?? []).compactMap { entry -> FHIRPrimitive<FHIRURI>? in
            guard case .observation(let observation)? = entry.resource,
                  observation.extension?.contains(where: { $0.value == .code(Self.electrocardiogramLineage.asFHIRStringPrimitive()) }) == true,
                  observation.code.coding?.first?.code?.value?.string == MeasurementCatalog.heartRate.code.code else {
                return nil
            }
            return entry.fullUrl
        }
        for fullURL in averageHeartRates {
            #expect(projection.failures.contains { $0.fullURL == fullURL && $0.error == .measurementNotMappable(id: "heart-rate") })
        }
        if goldenCase.name == "insulin-delivery-bolus" {
            #expect(projection.failures.map(\.error) == [.measurementNotMappable(id: "insulin-delivery")])
        }
    }
}

#endif
